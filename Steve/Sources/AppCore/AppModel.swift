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

    /// Start the scheduler: fires an immediate check then begins periodic checks.
    /// After each check propagates scheduler state onto the main-actor observable properties.
    public func start() async {
        await scheduler.start()
        await syncFromScheduler()
    }

    // MARK: — Scheduler → observable bridge

    /// Copies `isChecking` and `lastDerivedState` from the `CheckScheduler` actor
    /// onto this `@Observable` main-actor object so SwiftUI can observe them.
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
                // Rebuild the cache from the fresh snapshot.
                try? cacheStore.rebuild(from: snapshot)

                // Derive origin hashes from the snapshot (O).
                var originHashes: [String: String] = [:]
                for skill in snapshot.skills {
                    if let hash = try? cacheStore.contentHash(for: skill.name) {
                        originHashes[skill.name] = hash
                    }
                }

                // Derive cache hashes (C) — now equal to O after rebuild.
                // We compute them from disk so C and O use the same hash scheme.
                var cacheHashes: [String: String] = [:]
                for skill in snapshot.skills {
                    if let hash = try? cacheStore.contentHash(for: skill.name) {
                        cacheHashes[skill.name] = hash
                    }
                }

                // Installed-skills hashes (S) come from the injected provider.
                let installedHashes = installedSkills()

                let derivedState = StateEngine.derive(
                    skills: installedHashes,
                    cache: cacheHashes,
                    origin: originHashes
                )

                return .ok(derivedState)
            }
        }
    }
}

// MARK: — Default cache root

extension AppModel {
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
