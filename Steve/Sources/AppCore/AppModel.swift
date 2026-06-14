import Foundation
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
public final class AppModel: Sendable {

    // MARK: — Internal scheduler (accessible for testing + SwiftUI binding)

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
        automaticChecksEnabled: Bool = true
    ) {
        let cacheRootResolved = cacheRoot ?? AppModel.makeDefaultCacheRoot()
        let cacheStore = CacheStore(root: cacheRootResolved)
        let performCheck = AppModel.makePerformCheck(
            owner: owner, repo: repo, branch: branch,
            transport: transport,
            cacheStore: cacheStore
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
    public func start() async {
        await scheduler.start()
    }

    // MARK: — Factory: builds the performCheck closure the scheduler calls

    /// Builds the `performCheck` closure that wires `OriginClient` → `CacheStore`
    /// → `StateEngine`. Exposed as a static method so tests can invoke it directly
    /// without constructing a full `AppModel`.
    public static func makePerformCheck(
        owner: String,
        repo: String,
        branch: String,
        transport: HTTPTransport,
        cacheStore: CacheStore
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
                // networkError, rateLimited, fetchFailed — all non-destructive
                return .ok(nil)
            }

            switch outcome {
            case .ignored:
                return .ok(nil)

            case .unchanged:
                // Nothing moved; no new state derivation needed in this slice.
                return .ok(nil)

            case .updated(let snapshot):
                // Rebuild the cache from the fresh snapshot, then derive state.
                try? cacheStore.rebuild(from: snapshot)
                return .ok(nil)
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
}

// MARK: — Wall-clock SchedulerClock

/// The production clock: sleeps for real using `Task.sleep`.
public struct WallClock: SchedulerClock {
    public init() {}

    public func sleep(for duration: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
    }
}
