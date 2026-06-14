import Foundation
import Observation
#if SWIFT_PACKAGE
import Cache
import StateEngine
import OriginClient
import Scheduler
#endif

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

    // MARK: — Internal scheduler (accessible for testing + manual trigger)

    public let scheduler: CheckScheduler

    /// The task draining the scheduler's `stateUpdates` stream onto this main-actor
    /// object. Retained so it can be cancelled in `deinit`. `nonisolated(unsafe)` is
    /// safe here: a `Task` handle is `Sendable`, it is written exactly once on the
    /// main actor (in `start()`), and only read again from `deinit`, which runs after
    /// every other reference is gone — so there is no concurrent access.
    private nonisolated(unsafe) var stateObserver: Task<Void, Never>?

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
        installedSkills: @escaping @Sendable () -> [String: String] = AppModel.makeDefaultInstalledSkillsProvider()
    ) {
        let cacheRootResolved = cacheRoot ?? AppModel.makeDefaultCacheRoot()
        let cacheStore = CacheStore(root: cacheRootResolved)
        let performCheck = AppModel.makePerformCheck(
            owner: owner, repo: repo, branch: branch,
            transport: transport,
            cacheStore: cacheStore,
            installedSkills: installedSkills
        )
        self.scheduler = CheckScheduler(
            performCheck: performCheck,
            clock: clock,
            interval: interval,
            slowRetryInterval: slowRetryInterval,
            automaticChecksEnabled: automaticChecksEnabled
        )
    }

    deinit {
        stateObserver?.cancel()
    }

    /// Start the scheduler: fires an immediate check then begins periodic checks.
    /// Observable state is then kept live for EVERY check — launch, every timer
    /// tick, and manual triggers — by draining the scheduler's `stateUpdates` stream.
    public func start() async {
        // Begin draining the completion stream BEFORE the launch check fires so no
        // emission is missed. The stream buffers (newest-8) if this task hasn't yet
        // suspended on its first iteration, so launch-check emissions are never lost.
        startObservingSchedulerState()
        await scheduler.start()
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
    public static func makePerformCheck(
        owner: String,
        repo: String,
        branch: String,
        transport: HTTPTransport,
        cacheStore: CacheStore,
        installedSkills: @escaping @Sendable () -> [String: String] = AppModel.makeDefaultInstalledSkillsProvider()
    ) -> @Sendable () async -> CheckResult {
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
                return .originNotFound
            } catch {
                // networkError, rateLimited, fetchFailed — all transient, non-destructive.
                // Map to .transientError so the scheduler preserves its current cadence
                // (including any 404 slow-retry backoff) and last good DerivedState.
                return .transientError
            }

            switch outcome {
            case .ignored:
                return .ok(nil)

            case .unchanged:
                // Nothing moved; no new snapshot → no state derivation possible.
                return .ok(nil)

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

                return .ok(derivedState)
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

// MARK: — Wall-clock SchedulerClock

/// The production clock: sleeps for real using `Task.sleep`.
public struct WallClock: SchedulerClock {
    public init() {}

    public func sleep(for duration: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
    }
}
