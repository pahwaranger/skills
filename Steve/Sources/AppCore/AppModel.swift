import Foundation
import Observation
#if SWIFT_PACKAGE
import Cache
import StateEngine
import OriginClient
import Scheduler
import Installer
#endif

#if DEBUG
#if SWIFT_PACKAGE
import FixtureEngine
#endif
#endif

/// The two tabs hosted in the unified "Steve" window (Issue #45).
/// The dropdown sets `AppModel.selectedTab` before calling `openWindow(id: "main")`
/// so the window opens on the correct tab without any AppKit hacks.
public enum WindowTab: Equatable, Sendable {
    /// The Review tab — sidebar + diff pane (ReviewWindowView).
    case review
    /// The Settings tab — preferences form (SettingsView).
    case settings
}

/// The composition root: wires `OriginClient` → `CacheStore` → `StateEngine`
/// into a `performCheck` closure that the `CheckScheduler` drives.
///
/// Keeping this in an SPM target (rather than the Xcode-only app folder) makes
/// the wiring logic and the mapping from `OriginError` → `CheckResult` fully
/// unit-testable without a real network.
///
/// ## Observable state
/// `AppModel` is `@Observable` on the main actor so SwiftUI views re-render
/// whenever `isChecking` or `lastDerivedState` change. The `CheckScheduler`
/// actor's state is propagated onto the main actor after each check via an
/// `@MainActor` update hop.
@MainActor @Observable
public final class AppModel {

    // MARK: — Observable properties (SwiftUI-facing)

    /// True while a check is in flight. Drives the pulsing menu-bar icon state.
    public private(set) var isChecking: Bool = false

    /// The most recently derived skill sync state. `nil` until the first
    /// successful check that produces an origin snapshot.
    public private(set) var lastDerivedState: DerivedState?

    /// The date the most recent check completed (success or failure). `nil` until the
    /// first check finishes. Drives "checked X ago" in the status-line wording (#15).
    public private(set) var lastCheckDate: Date?

    /// The error kind from the most recent failed check, or `nil` if the last check
    /// succeeded. Drives the 4 error status-line wordings (#15).
    public private(set) var lastCheckError: CheckError?

    /// The resolved default branch from the GitHub API. Populated after the first
    /// successful `resolveDefaultBranch()` call; `nil` until then. Used by the skill
    /// row links so they point to the live default branch rather than a hardcoded value.
    public private(set) var resolvedDefaultBranch: String?

    /// The skill name that the Review window should scroll to / pre-select when it opens.
    /// Set by the dropdown row action before calling `openWindow(id: "main")`.
    /// `ReviewWindowView` observes this via `onChange` and clears it after consuming.
    public var reviewFocusSkill: String?

    /// Which tab is currently selected in the unified "Steve" window (Issue #45).
    /// Defaults to `.review`. The dropdown sets this before calling `openWindow(id: "main")`
    /// so the window opens on the correct tab — mirroring the `reviewFocusSkill` channel.
    public var selectedTab: WindowTab = .review

    /// Atomically returns the current `reviewFocusSkill` and clears it to `nil`.
    ///
    /// `ReviewWindowView` calls this instead of manually reading + zeroing the property,
    /// so the consume-and-clear is a single, testable model operation. Callers receive
    /// the skill name that was set by the dropdown (or `nil` if no skill was pending),
    /// and the channel is left clean for the next open.
    @discardableResult
    public func consumeReviewFocusSkill() -> String? {
        let skill = reviewFocusSkill
        reviewFocusSkill = nil
        return skill
    }

    /// The immutable origin snapshot captured when the Review window opens.
    /// `nil` when no Review window is open or before the first successful check.
    /// Background scheduler checks update `lastDerivedState` but must NOT replace this.
    /// Setter is internal (not private) so the `ReviewSession.swift` extension can write it.
    public internal(set) var reviewSession: ReviewSession?

    /// The commit SHA from the most recent successful origin check (200 response).
    /// Set by `applyCheckResult` via `applyOriginSHA(_:)` after each update.
    /// Used by `openReviewSession()` to snapshot the current SHA.
    /// Setter is internal so the `ReviewSession.swift` extension can write it.
    public internal(set) var lastKnownOriginSHA: String?

    /// Per-skill file contents from the most recent successful origin check (200 response).
    /// Populated alongside `lastKnownOriginSHA` by `applyOriginSnapshot(_:_:)`.
    /// Used by `openReviewSession()` to embed skill files in the immutable session so
    /// Update/Skip can commit without an extra network round-trip (Slice 10 / ADR 0007).
    /// Setter is internal so the `ReviewSession.swift` extension can write it.
    public internal(set) var lastOriginSkillFiles: [String: [String: Data]] = [:]

    // MARK: — Stored owner/repo (used for GitHub links in the view)

    /// The GitHub owner used to construct skill-directory links.
    public let owner: String
    /// The GitHub repository used to construct skill-directory links.
    public let repo: String
    /// The init-time branch (used as a fallback for GitHub links before
    /// `resolvedDefaultBranch` is populated by `OriginClient.resolveDefaultBranch()`).
    public let branch: String

    // MARK: — Internal scheduler (accessible for testing + manual trigger)

    public let scheduler: CheckScheduler

    /// The task draining the scheduler's `stateUpdates` stream onto this main-actor
    /// object. Retained so it can be cancelled in `deinit`. `nonisolated(unsafe)` is
    /// safe here: a `Task` handle is `Sendable`, it is written exactly once on the
    /// main actor (in `start()`), and only read again from `deinit`, which runs after
    /// every other reference is gone — so there is no concurrent access.
    private nonisolated(unsafe) var stateObserver: Task<Void, Never>?

    /// OriginClient instance retained for `resolveDefaultBranch()`. Kept private;
    /// only the main-actor method below calls it via a Task hop to the actor.
    private let _originClient: OriginClient

    /// The install engine for committing Update/Skip actions in the Review window.
    /// Injected at init so tests can supply a fully-configured engine; production
    /// supplies the real directories. `nil` in unit tests that don't test install.
    public let installEngine: InstallEngine?

    /// The transport retained for SHA re-validation in `performUpdate`/`performSkip`.
    /// Same transport used by the OriginClient so no extra connections are opened.
    /// Internal (not private) so ReviewSession.swift extension can access it.
    let _transport: HTTPTransport

    // MARK: — Init

    public init(
        owner: String,
        repo: String,
        branch: String,
        transport: HTTPTransport,
        cacheRoot: URL? = nil,
        clock: any SchedulerClock = WallClock(),
        interval: TimeInterval = 3600,
        slowRetryInterval: TimeInterval = 21600,
        automaticChecksEnabled: Bool = true,
        /// Provider for installed-skills content hashes. Injected so tests can
        /// supply deterministic values without touching `~/.claude/skills`.
        /// The production default scans the real skills directory.
        installedSkills: @escaping @Sendable () -> [String: String] = AppModel.makeDefaultInstalledSkillsProvider(),
        /// Install engine for Update/Skip actions. Injected so tests can supply
        /// a configured engine with temp directories. Production supplies the real
        /// engine via `SteveApp.swift`. `nil` in tests that don't test install.
        installEngine: InstallEngine? = nil
    ) {
        self.owner = owner
        self.repo = repo
        self.branch = branch
        self._transport = transport
        self._originClient = OriginClient(owner: owner, repo: repo, transport: transport)
        self.installEngine = installEngine
        let cacheRootResolved = cacheRoot ?? AppModel.makeDefaultCacheRoot()
        let cacheStore = CacheStore(root: cacheRootResolved)
        let basePerformCheck = AppModel.makePerformCheck(
            owner: owner, repo: repo, branch: branch,
            transport: transport,
            cacheStore: cacheStore,
            installedSkills: installedSkills
        )
        // A Sendable weak-ref box set after init so the performCheck wrapper can
        // call back into self without a strong reference cycle.
        let selfBox = WeakBox<AppModel>()
        // Wrap performCheck to intercept the result and update lastCheckDate/lastCheckError
        // on the main actor after each check (for status-line wording, Slice 6).
        // Also intercept the origin SHA + per-skill files from each successful update so
        // `openReviewSession()` can snapshot them without an extra network round-trip (Slice 10).
        let performCheck: @Sendable () async -> CheckResult = {
            let (result, sha, skillFiles) = await basePerformCheck()
            await MainActor.run {
                selfBox.value?.applyCheckResult(result)
                if let sha { selfBox.value?.applyOriginSnapshot(sha, skillFiles: skillFiles) }
            }
            return result
        }
        self.scheduler = CheckScheduler(
            performCheck: performCheck,
            clock: clock,
            interval: interval,
            slowRetryInterval: slowRetryInterval,
            automaticChecksEnabled: automaticChecksEnabled
        )
        // Wire the box to self now that init is complete.
        selfBox.value = self
    }

    deinit {
        stateObserver?.cancel()
    }

    /// Start the scheduler: fires an immediate check then begins periodic checks.
    /// Observable state is then kept live for EVERY check — launch, every timer
    /// tick, and manual triggers — by draining the scheduler's `stateUpdates` stream.
    /// Also resolves the repository's default branch at launch so GitHub links use the
    /// live branch rather than the hardcoded init-time value (Slice 6 AC).
    public func start() async {
        // Begin draining the completion stream BEFORE the launch check fires so no
        // emission is missed. The stream buffers (newest-8) if this task hasn't yet
        // suspended on its first iteration, so launch-check emissions are never lost.
        startObservingSchedulerState()
        // Resolve the default branch concurrently with the launch check so it doesn't
        // add latency to the first status update. Both are awaited before start() returns,
        // making the result deterministically available to callers (and to tests).
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.resolveAndStoreDefaultBranch() }
            group.addTask { await self.scheduler.start() }
        }
        // Guarantee the observable reflects the launch result *synchronously* on
        // return, so callers asserting immediately after `start()` are deterministic
        // (the stream hop is async). Subsequent checks are covered by the stream.
        await syncFromScheduler()
    }

    /// Manually trigger a check (wired to "Check for updates"). Awaiting this returns
    /// only after the observable state reflects the check's result.
    public func triggerCheck() async {
        await scheduler.triggerCheck()
        await syncFromScheduler()
    }

    /// Resolves the repository's default branch from the GitHub API and stores it in
    /// `resolvedDefaultBranch`. Called once at launch (from `SteveApp.swift`) so that
    /// skill-row GitHub links point to the live default branch rather than the hardcoded
    /// init-time value. Falls back silently to `nil` (which the view handles by using
    /// the init-time `branch`).
    public func resolveAndStoreDefaultBranch() async {
        guard let resolved = try? await _originClient.resolveDefaultBranch() else { return }
        resolvedDefaultBranch = resolved
    }

    // MARK: — Scheduler → observable bridge

    /// Drains the scheduler's `stateUpdates` stream, copying each emitted snapshot
    /// onto this `@Observable` main-actor object. This is the mechanism that makes
    /// `isChecking`/`lastDerivedState` update on EVERY check (timer ticks included),
    /// not just the one-shot sync after launch. Only `Sendable` value types cross the
    /// actor → main-actor boundary, so there is no data race.
    private func startObservingSchedulerState() {
        guard stateObserver == nil else { return }
        stateObserver = Task { [weak self] in
            guard let stream = self?.scheduler.stateUpdates else { return }
            for await snapshot in stream {
                guard let self else { return }
                self.isChecking = snapshot.isChecking
                self.lastDerivedState = snapshot.lastDerivedState
            }
        }
    }

    /// One-shot copy of `isChecking`/`lastDerivedState` from the actor, used to make
    /// the observable state deterministic on return from an awaited check.
    private func syncFromScheduler() async {
        let checking = await scheduler.isChecking
        let state = await scheduler.lastDerivedState
        isChecking = checking
        lastDerivedState = state
    }

    /// Records the outcome of a completed check as `lastCheckDate` and `lastCheckError`.
    /// Called on the main actor via a hop in the wrapped `performCheck` closure.
    /// On success (`.ok`) the error is cleared; on any failure the error is set.
    @MainActor
    func applyCheckResult(_ result: CheckResult) {
        lastCheckDate = Date()
        switch result {
        case .ok:
            lastCheckError = nil
        case .originNotFound:
            lastCheckError = .originNotFound
        case .transientError(let reason):
            // Map each TransientReason to the matching CheckError so all error
            // wordings are reachable in StatusLine (network / rate-limited / fetch-failed).
            switch reason {
            case .network:
                lastCheckError = .networkError
            case .rateLimited(let resetAt):
                lastCheckError = .rateLimited(resetAt: resetAt)
            case .fetchFailed:
                lastCheckError = .fetchFailed
            }
        }
    }

    /// Records the origin SHA and per-skill file contents from a successful 200 check response.
    /// Called on the main actor via a hop in the wrapped `performCheck` closure.
    /// Both are snapshotted by `openReviewSession()` to produce an immutable `ReviewSession`
    /// without an extra network round-trip (Slice 10 / ADR 0006 / ADR 0007).
    @MainActor
    func applyOriginSnapshot(_ sha: String, skillFiles: [String: [String: Data]]) {
        lastKnownOriginSHA = sha
        lastOriginSkillFiles = skillFiles
    }

    // MARK: — Factory: builds the performCheck closure the scheduler calls

    /// Builds the `performCheck` closure that wires `OriginClient` → `CacheStore`
    /// → `StateEngine`. Exposed as a static method so tests can invoke it directly
    /// without constructing a full `AppModel`.
    ///
    /// ## Installed-skills versioning
    /// The installed hash for each skill is computed by the injected `installedSkills`
    /// provider. In production this uses `CacheStore.contentHash(for:)` applied to each
    /// skill directory under `~/.claude/skills/` — the same SHA256 scheme the cache
    /// uses for origin skills, so hashes from S, C, and O are directly comparable.
    /// In tests, a deterministic dictionary is injected instead.
    ///
    /// ## Return value
    /// Returns a closure that produces a `(CheckResult, String?, [String: [String: Data]])` tuple.
    /// The second element is the origin commit SHA from a successful `.updated` response,
    /// the third is the per-skill file map from the same snapshot (both `nil`/empty for other outcomes).
    /// The caller (the wrapped `performCheck` in `AppModel.init`) uses these to keep
    /// `lastKnownOriginSHA` and `lastOriginSkillFiles` live for `openReviewSession()` without
    /// an extra network round-trip (Slice 10 / ADR 0006 / ADR 0007).
    public static func makePerformCheck(
        owner: String,
        repo: String,
        branch: String,
        transport: HTTPTransport,
        cacheStore: CacheStore,
        installedSkills: @escaping @Sendable () -> [String: String] = AppModel.makeDefaultInstalledSkillsProvider()
    ) -> @Sendable () async -> (CheckResult, String?, [String: [String: Data]]) {
        let client = OriginClient(owner: owner, repo: repo, transport: transport)
        return {
            // Read cached ETag/SHA for conditional request.
            let (knownETag, knownSHA): (String?, String?)
            if let meta = try? cacheStore.readMetadata() {
                knownETag = meta.etag.isEmpty ? nil : meta.etag
                knownSHA = meta.commitSHA.isEmpty ? nil : meta.commitSHA
            } else {
                knownETag = nil
                knownSHA = nil
            }

            let outcome: CheckOutcome
            do {
                outcome = try await client.check(
                    branch: branch,
                    knownETag: knownETag,
                    knownSHA: knownSHA
                )
            } catch OriginError.originNotFound {
                return (.originNotFound, nil, [:])
            } catch OriginError.rateLimited(let retryAt) {
                // 403 with X-RateLimit-Reset — carry the reset date so the UI can show the
                // countdown wording ("GitHub rate limit reached · retries H:MM").
                return (.transientError(.rateLimited(resetAt: retryAt)), nil, [:])
            } catch OriginError.fetchFailed {
                // Tarball corrupt or extraction error — carry the reason so the UI can show
                // "Origin fetch failed…" instead of the generic network-error wording.
                return (.transientError(.fetchFailed), nil, [:])
            } catch {
                // networkError (unreachable / timeout / 5xx) — all other failures are
                // network-level; the scheduler treats them identically but the UI shows
                // "Couldn't reach origin…".
                return (.transientError(.network), nil, [:])
            }

            switch outcome {
            case .ignored:
                return (.ok(nil), nil, [:])

            case .unchanged:
                // Nothing moved; no new snapshot → no state derivation possible.
                return (.ok(nil), nil, [:])

            case .updated(let snapshot):
                // Read the CURRENT cache hashes (C) from disk BEFORE any mutation.
                // C is the last-seen / acknowledged mirror; comparing the fresh origin
                // against it is what makes `.updateAvailable` reachable (O ≠ C). Walking
                // the live cache first — never rebuilding it to O here — is the fix for
                // the bug where a pre-derive rebuild forced C == O and collapsed every
                // result to `.skipped`. Per ADR 0006/0007 the acknowledged-cache update
                // (O→Cache) belongs to user Update/Skip actions, NOT this periodic check.
                var cacheHashes: [String: String] = [:]
                for name in cacheStore.cachedSkillNames() {
                    if let hash = try? cacheStore.contentHash(for: name) {
                        cacheHashes[name] = hash
                    }
                }

                // Compute origin hashes (O) from the fresh snapshot WITHOUT touching the
                // live cache: materialise the snapshot into a throwaway CacheStore and hash
                // there. This uses the same SHA256 (filename, bytes) scheme as the real
                // cache, so S, C and O are directly comparable.
                let originHashes = AppModel.originHashes(from: snapshot)

                // Installed-skills hashes (S) come from the injected provider.
                let installedHashes = installedSkills()

                let derivedState = StateEngine.derive(
                    skills: installedHashes,
                    cache: cacheHashes,
                    origin: originHashes
                )

                // Self-heal persistence is intentionally NOT performed here. ADR 0006's
                // self-heal (C ← O when S == O) is idempotent and can be persisted by a
                // later user-action slice; persisting it in the background check is only
                // ever safe for names in `derivedState.selfHealed` and must never touch a
                // skill that is `.updateAvailable` (doing so would re-acknowledge O and
                // destroy the very signal this fix restores). Keeping the periodic check
                // non-mutating keeps "last seen" honest (ADR 0007 cache-after-success).
                _ = derivedState.selfHealed

                // Build per-skill file map for ReviewSession: captured at window-open so
                // Update/Skip can commit without a second network round-trip (Slice 10).
                var skillFiles: [String: [String: Data]] = [:]
                for skill in snapshot.skills {
                    skillFiles[skill.name] = skill.files
                }

                return (.ok(derivedState), snapshot.commitSHA, skillFiles)
            }
        }
    }
}

// MARK: — Default cache root

extension AppModel {
    /// Computes per-skill content hashes (O) for an origin snapshot WITHOUT mutating
    /// any live cache. The snapshot's in-memory files are written into a throwaway
    /// `CacheStore` and hashed with the same SHA256 (filename, bytes) scheme the cache
    /// uses, so the resulting O hashes are directly comparable with C and S.
    nonisolated static func originHashes(from snapshot: OriginSnapshot) -> [String: String] {
        let tmpRoot = FileManager.default.temporaryDirectory
            .appending(path: "steve-origin-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: tmpRoot) }

        let tmpStore = CacheStore(root: tmpRoot)
        var hashes: [String: String] = [:]
        for skill in snapshot.skills {
            try? tmpStore.writeSkillFiles(named: skill.name, files: skill.files)
            if let hash = try? tmpStore.contentHash(for: skill.name) {
                hashes[skill.name] = hash
            }
        }
        return hashes
    }

    public static func makeDefaultCacheRoot() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                   in: .userDomainMask).first!
        return appSupport.appending(path: "Steve/cache", directoryHint: .isDirectory)
    }

    /// Builds a provider that scans the real `~/.claude/skills/` directory and
    /// computes content hashes using a temporary `CacheStore`. Used in production;
    /// tests inject a deterministic dictionary instead.
    public static func makeDefaultInstalledSkillsProvider() -> @Sendable () -> [String: String] {
        return {
            let skillsDir = FileManager.default.homeDirectoryForCurrentUser
                .appending(path: ".claude/skills", directoryHint: .isDirectory)

            guard FileManager.default.fileExists(atPath: skillsDir.path(percentEncoded: false)),
                  let names = try? FileManager.default.contentsOfDirectory(atPath: skillsDir.path(percentEncoded: false))
            else { return [:] }

            // Use a temporary CacheStore rooted one level above skills/ so its
            // contentHash(for:) method can walk the real skill directories.
            // Each skill's hash is SHA256 over (filename, contents) pairs — the same
            // algorithm the Cache and OriginClient use, making S/C/O hashes comparable.
            let tmpRoot = FileManager.default.temporaryDirectory
                .appending(path: "steve-installed-\(UUID().uuidString)", directoryHint: .isDirectory)
            let tmpSkillsDir = tmpRoot.appending(path: "skills", directoryHint: .isDirectory)

            var result: [String: String] = [:]
            for name in names {
                let src = skillsDir.appending(path: name, directoryHint: .isDirectory)
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: src.path(percentEncoded: false), isDirectory: &isDir),
                      isDir.boolValue else { continue }

                // Symlink the real skill dir into the tmp tree so contentHash can find it.
                let dst = tmpSkillsDir.appending(path: name, directoryHint: .isDirectory)
                try? FileManager.default.createDirectory(at: tmpSkillsDir, withIntermediateDirectories: true)
                try? FileManager.default.createSymbolicLink(at: dst, withDestinationURL: src)

                let store = CacheStore(root: tmpRoot)
                if let hash = try? store.contentHash(for: name) {
                    result[name] = hash
                }
            }
            try? FileManager.default.removeItem(at: tmpRoot)
            return result
        }
    }
}

// MARK: — Direct-seed preview initializer (route b)

#if DEBUG

/// Stub transport for preview direct-seeding. Routes all requests to a handler;
/// used in the direct-seed factory so previews don't make real network calls.
private final class PreviewStubTransport: HTTPTransport {
    private let handler: @Sendable (URL) async throws -> HTTPResponse

    init(handler: @escaping @Sendable (URL) async throws -> HTTPResponse) {
        self.handler = handler
    }

    func get(url: URL, headers: [String: String]) async throws -> HTTPResponse {
        try await handler(url)
    }
}

extension AppModel {
    /// Direct-seed initializer for SwiftUI previews (route b).
    /// Directly assigns `lastDerivedState` and `reviewSession` from a `FixtureScenario`,
    /// bypassing the async sandbox-derive pipeline.
    /// Compiled out of Release builds (ADR 0009).
    ///
    /// - Parameters:
    ///   - scenario: The `FixtureScenario` providing target states and origin files.
    ///   - owner, repo, branch: Stored for GitHub URL construction (same as production init).
    ///
    /// Returns an `AppModel` with seeded state ready for preview rendering.
    public static func directSeed(
        from scenario: FixtureScenario,
        owner: String = "test",
        repo: String = "test",
        branch: String = "main"
    ) -> AppModel {
        // Build a DerivedState with per-skill states from the scenario.
        // Map scenario entries -> states map for StateEngine.
        var states: [String: SkillState] = [:]
        for entry in scenario.skills {
            states[entry.name] = entry.targetState
        }

        let derivedState = DerivedState(
            states: states,
            attention: states.values.contains(where: { $0 != .upToDate }),
            selfHealed: []
        )

        // Build a ReviewSession with per-skill origin files from the scenario.
        var skillFiles: [String: [String: Data]] = [:]
        for entry in scenario.skills {
            if let originFiles = entry.originFiles {
                skillFiles[entry.name] = originFiles
            }
        }

        let reviewSession = ReviewSession(
            originSHA: "direct-seed-sha",
            skillFiles: skillFiles
        )

        // Create an AppModel with a stub transport (previews don't make network calls).
        let stubTransport = PreviewStubTransport { _ in
            HTTPResponse(status: 404, headers: [:], body: Data())
        }

        let model = AppModel(
            owner: owner,
            repo: repo,
            branch: branch,
            transport: stubTransport,
            automaticChecksEnabled: false
        )

        // Directly assign the seeded state.
        model.lastDerivedState = derivedState
        model.reviewSession = reviewSession

        return model
    }
}

#endif

// MARK: — Wall-clock SchedulerClock

/// The production clock: sleeps for real using `Task.sleep`.
public struct WallClock: SchedulerClock {
    public init() {}

    public func sleep(for duration: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
    }
}
