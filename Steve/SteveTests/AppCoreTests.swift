import Testing
import Foundation
import Cache
import OriginClient
import StateEngine
import Scheduler
@testable import AppCore

// MARK: — Stub transport for AppCore tests

/// Routes each request to a closure; records all calls.
final class AppCoreStubTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _recorded: [URL] = []
    private let handler: @Sendable (URL) async throws -> HTTPResponse

    var recorded: [URL] { lock.withLock { _recorded } }

    init(handler: @escaping @Sendable (URL) async throws -> HTTPResponse) {
        self.handler = handler
    }

    func get(url: URL, headers: [String: String]) async throws -> HTTPResponse {
        lock.withLock { _recorded.append(url) }
        return try await handler(url)
    }
}

// MARK: — Shared test helpers (thread-safe counter + gated clock)

/// Thread-safe call counter used by the AppCore tests.
final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0
    var value: Int { lock.withLock { _value } }
    func increment() { lock.withLock { _value += 1 } }
}

/// A clock whose `sleep` blocks until `releaseOne()` is called for that sleep,
/// letting tests drive timer-loop ticks deterministically.
final class AppCoreGatedClock: SchedulerClock, @unchecked Sendable {
    private let lock = NSLock()
    private var _sleepCount = 0
    private var _releaseCount = 0
    var sleepCount: Int { lock.withLock { _sleepCount } }
    func releaseOne() { lock.withLock { _releaseCount += 1 } }
    func sleep(for duration: TimeInterval) async throws {
        let myIndex = lock.withLock { () -> Int in
            _sleepCount += 1
            return _sleepCount
        }
        while lock.withLock({ _releaseCount < myIndex }) && !Task.isCancelled {
            await Task.yield()
        }
    }
}

// MARK: — Helpers for building a fake tarball origin snapshot

/// Builds a minimal fake tarball HTTPResponse containing one skill directory
/// with one file, so the OriginClient can extract it into an OriginSnapshot.
private func fakeSnapshotTransport(
    sha: String,
    skillName: String,
    fileContents: String
) -> AppCoreStubTransport {
    AppCoreStubTransport { url in
        let urlString = url.absoluteString
        if urlString.contains("commits") {
            // Probe response: 200 with bare SHA body
            return HTTPResponse(
                status: 200,
                headers: ["ETag": "\"etag-\(sha)\""],
                body: Data((sha + "\n").utf8)
            )
        } else if urlString.contains("tar.gz") {
            // Tarball response with a fake skill
            let tarData = try makeFakeTarGz(skillName: skillName, fileContents: fileContents)
            return HTTPResponse(status: 200, headers: [:], body: tarData)
        }
        return HTTPResponse(status: 404, headers: [:], body: Data())
    }
}

// MARK: — AppModel composition / mapping tests

@Suite("AppModel")
struct AppModelTests {

    // MARK: — originNotFound surfaces as CheckResult.originNotFound

    @Test func originNotFoundSurfacesFromOriginClientThroughPipeline() async throws {
        // A 404 from the transport must surface as CheckResult.originNotFound,
        // which causes the scheduler's lastOutcomeWas404 to be set (observable via slow-retry).
        // We test the performCheck closure returned by AppModel directly.

        let transport = AppCoreStubTransport { _ in
            HTTPResponse(status: 404, headers: [:], body: Data())
        }

        let cacheDir = FileManager.default.temporaryDirectory
            .appending(path: "appcore-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cacheDir) }

        let result = await AppModel.makePerformCheck(
            owner: "o", repo: "r", branch: "main",
            transport: transport,
            cacheStore: CacheStore(root: cacheDir),
            installedSkills: { [:] }
        )()

        guard case .originNotFound = result else {
            Issue.record("expected .originNotFound, got \(result)")
            return
        }
    }

    // MARK: — Successful check returns .ok(DerivedState) with meaningful state

    @Test func successfulCheckDerivesUpdateAvailableForNewlySeenSkill() async throws {
        // The periodic check derives state against the PRE-CHECK cache, which it
        // must NOT wholesale-rebuild (ADR 0006/0007: the acknowledged-cache update
        // belongs to user Update/Skip actions, not background checks).
        //
        // Setup:
        //   - Origin has "alpha" with content "skill content v2" (O = hash of that).
        //   - Cache is empty for "alpha" (C = nil — never seen / not acknowledged).
        //   - Installed skills: "alpha" → an arbitrary hash that differs from O (S != O).
        //
        // Expected (StateEngine.derive): o != nil, s != o, c (nil) != o → .updateAvailable,
        //   attention == true. This is the bug-fix assertion: if the check rebuilt the
        //   cache to O before deriving, C would equal O and this would be .skipped.
        let sha = "abc123"
        let skillFileContent = "skill content v2"
        let transport = fakeSnapshotTransport(
            sha: sha,
            skillName: "alpha",
            fileContents: skillFileContent
        )

        let cacheDir = FileManager.default.temporaryDirectory
            .appending(path: "appcore-derive-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cacheDir) }

        let installedHash = "installed-hash-v1-different"
        let result = await AppModel.makePerformCheck(
            owner: "o", repo: "r", branch: "main",
            transport: transport,
            cacheStore: CacheStore(root: cacheDir),
            installedSkills: { ["alpha": installedHash] }
        )()

        guard case .ok(let derivedState) = result else {
            Issue.record("expected .ok(derivedState), got \(result)")
            return
        }

        guard let state = derivedState else {
            Issue.record("expected a non-nil DerivedState after update, got nil")
            return
        }

        // C (nil) != O and S != O → .updateAvailable, attention == true.
        #expect(state.states["alpha"] == .updateAvailable,
                "alpha should be .updateAvailable (origin moved vs an empty/unacknowledged cache, installed differs)")
        #expect(state.attention == true,
                "attention should be true when a skill is .updateAvailable")
    }

    @Test func successfulCheckDerivesUpdateAvailableWhenOriginMovedPastAcknowledgedCache() async throws {
        // Genuine updateAvailable with a NON-empty cache: the cache holds an older,
        // previously-acknowledged version of "alpha" (C != O), and the installed copy
        // also differs from origin (S != O). This is the canonical "Origin moved since
        // last seen, not installed" case from ADR 0006.
        //
        // The check must derive against this PRE-CHECK cache (C = old hash) — NOT rebuild
        // it to O first. With the bug present, the rebuild makes C == O → .skipped, and
        // this test fails.
        let sha = "movedsha"
        let originContent = "alpha NEW content"          // O
        let transport = fakeSnapshotTransport(
            sha: sha, skillName: "alpha", fileContents: originContent
        )

        let cacheDir = FileManager.default.temporaryDirectory
            .appending(path: "appcore-moved-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cacheDir) }

        // Pre-seed the live cache with the OLD acknowledged version of alpha (C != O).
        // Same filename ("SKILL.md") so C and O hashes are computed over comparable trees.
        let cacheStore = CacheStore(root: cacheDir)
        try cacheStore.writeSkillFiles(named: "alpha", files: ["SKILL.md": Data("alpha OLD content".utf8)])
        try cacheStore.writeMetadata(CacheMetadata(
            commitSHA: "oldsha", etag: "", lastChecked: Date(timeIntervalSinceReferenceDate: 0), skipState: [:]
        ))
        let preCheckCacheHash = try cacheStore.contentHash(for: "alpha")

        // Installed copy differs from origin too (S != O). Reuse the pre-check cache hash
        // as a convenient deterministic value that is known to differ from O.
        let result = await AppModel.makePerformCheck(
            owner: "o", repo: "r", branch: "main",
            transport: transport,
            cacheStore: cacheStore,
            installedSkills: { ["alpha": preCheckCacheHash] }
        )()

        guard case .ok(let derivedState) = result, let state = derivedState else {
            Issue.record("expected .ok(non-nil derivedState), got \(result)")
            return
        }
        #expect(state.states["alpha"] == .updateAvailable,
                "Origin moved past the acknowledged cache (O != C) and is not installed → .updateAvailable")
        #expect(state.attention == true)

        // Cache-mutation policy: the periodic check must NOT have rebuilt the cache to O.
        // The acknowledged mirror still holds the OLD content (C unchanged).
        let postCheckCacheHash = try cacheStore.contentHash(for: "alpha")
        #expect(postCheckCacheHash == preCheckCacheHash,
                "periodic check must not wholesale-rebuild the cache to O (ADR 0006/0007)")
    }

    @Test func successfulCheckDerivesSkippedWhenCacheAlreadyAcknowledgedOrigin() async throws {
        // The .skipped case, correctly named: the cache already equals origin
        // (C == O — the user previously acknowledged this exact origin version),
        // and the installed copy differs (S != O). Per ADR 0006: Skipped == C == O and S != O.
        //
        // We seed the cache with the SAME content the origin tarball will return, so
        // C == O at derive time WITHOUT relying on the check rebuilding the cache.
        let sha = "ackedsha"
        let originContent = "alpha acknowledged content"     // C == O
        let transport = fakeSnapshotTransport(
            sha: sha, skillName: "alpha", fileContents: originContent
        )

        let cacheDir = FileManager.default.temporaryDirectory
            .appending(path: "appcore-skipped-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cacheDir) }

        // Seed the cache to match origin exactly (same filename + bytes) → C == O.
        let cacheStore = CacheStore(root: cacheDir)
        try cacheStore.writeSkillFiles(named: "alpha", files: ["SKILL.md": Data(originContent.utf8)])
        try cacheStore.writeMetadata(CacheMetadata(
            commitSHA: sha, etag: "", lastChecked: Date(timeIntervalSinceReferenceDate: 0), skipState: [:]
        ))

        let result = await AppModel.makePerformCheck(
            owner: "o", repo: "r", branch: "main",
            transport: transport,
            cacheStore: cacheStore,
            installedSkills: { ["alpha": "installed-differs-from-origin"] }   // S != O
        )()

        guard case .ok(let derivedState) = result, let state = derivedState else {
            Issue.record("expected .ok(non-nil derivedState), got \(result)")
            return
        }
        // C == O, S != O → .skipped, attention = false.
        #expect(state.states["alpha"] == .skipped,
                "cache already matches origin (acknowledged) and installed differs → .skipped")
        #expect(state.attention == false)
    }

    @Test func unchangedOriginReturnsOkNilState() async throws {
        // 304 → no snapshot available → .ok(nil) is the correct result.
        // StateEngine cannot be called without origin hashes from a snapshot.
        let transport = AppCoreStubTransport { _ in
            HTTPResponse(status: 304, headers: [:], body: Data())
        }

        let cacheDir = FileManager.default.temporaryDirectory
            .appending(path: "appcore-304-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cacheDir) }

        let result = await AppModel.makePerformCheck(
            owner: "o", repo: "r", branch: "main",
            transport: transport,
            cacheStore: CacheStore(root: cacheDir),
            installedSkills: { [:] }
        )()

        guard case .ok(let state) = result else {
            Issue.record("expected .ok for 304, got \(result)")
            return
        }
        #expect(state == nil, "304 (unchanged) should produce .ok(nil) — no new snapshot to derive from")
    }

    // MARK: — networkError / rateLimited map to .transientError (not .ok)

    @Test func networkErrorReturnsTransientError() async throws {
        // 5xx → networkError → .transientError (must NOT be .ok so slow-retry is preserved)
        let transport = AppCoreStubTransport { _ in
            HTTPResponse(status: 503, headers: [:], body: Data())
        }

        let cacheDir = FileManager.default.temporaryDirectory
            .appending(path: "appcore-5xx-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cacheDir) }

        let result = await AppModel.makePerformCheck(
            owner: "o", repo: "r", branch: "main",
            transport: transport,
            cacheStore: CacheStore(root: cacheDir),
            installedSkills: { [:] }
        )()

        guard case .transientError = result else {
            Issue.record("expected .transientError for networkError, got \(result)")
            return
        }
    }

    @Test func rateLimitedReturnsTransientError() async throws {
        // 403 → rateLimited → .transientError
        let transport = AppCoreStubTransport { _ in
            HTTPResponse(status: 403, headers: ["X-RateLimit-Reset": "9999999999"], body: Data())
        }

        let cacheDir = FileManager.default.temporaryDirectory
            .appending(path: "appcore-ratelimit-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cacheDir) }

        let result = await AppModel.makePerformCheck(
            owner: "o", repo: "r", branch: "main",
            transport: transport,
            cacheStore: CacheStore(root: cacheDir),
            installedSkills: { [:] }
        )()

        guard case .transientError = result else {
            Issue.record("expected .transientError for rateLimited, got \(result)")
            return
        }
    }

    // MARK: — Observable state: isChecking and lastDerivedState update

    @Test @MainActor func observableLastDerivedStateUpdatesAfterSuccessfulCheck() async throws {
        // AppModel is @Observable; after a successful check that yields a known DerivedState,
        // model.lastDerivedState must reflect the derived output on the main actor.
        //
        // We inject a performCheck-like stub via the scheduler path: build an AppModel
        // whose makePerformCheck is wired so the check produces a known DerivedState,
        // then assert model.lastDerivedState matches after start().

        let sha = "obs-sha"
        let transport = fakeSnapshotTransport(sha: sha, skillName: "omega", fileContents: "omega v1")

        let cacheDir = FileManager.default.temporaryDirectory
            .appending(path: "appcore-obs-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cacheDir) }

        // omega not installed, empty (unacknowledged) cache → O != nil, C nil != O, S nil
        // → .updateAvailable (the periodic check does not pre-acknowledge via a rebuild).
        let model = AppModel(
            owner: "o", repo: "r", branch: "main",
            transport: transport,
            cacheRoot: cacheDir,
            automaticChecksEnabled: false,
            installedSkills: { [:] }
        )

        await model.start()

        // After start() completes, observable properties must reflect scheduler state.
        #expect(model.isChecking == false, "isChecking should be false after check completes")
        guard let state = model.lastDerivedState else {
            Issue.record("lastDerivedState should be non-nil after a successful update check")
            return
        }
        #expect(state.states["omega"] == .updateAvailable)
        #expect(state.attention == true)
    }

    @Test @MainActor func observableStateUpdatesOnEveryCheckNotJustLaunch() async throws {
        // BLOCKER 2: the @Observable AppModel must reflect the scheduler's
        // isChecking / lastDerivedState after EVERY check — not only the launch check.
        //
        // We drive a SECOND check via the manual triggerCheck() path (a check that is
        // NOT the launch check) and require the observable lastDerivedState to update
        // to the second check's result. With the old "sync once after start()" bridge,
        // model.lastDerivedState stays at the launch value and this test FAILS.
        //
        // Mechanism: the transport returns 304 (unchanged → .ok(nil)) on the FIRST probe
        // and a 200 + tarball (→ a non-nil DerivedState) on the SECOND probe. So:
        //   launch check  → lastDerivedState == nil
        //   manual trigger → lastDerivedState == <derived state for "zeta">
        let probeCount = CallCounter()
        let sha = "every-check-sha"
        let transport = AppCoreStubTransport { url in
            let urlString = url.absoluteString
            if urlString.contains("commits") {
                // Probe: first call 304 (unchanged), second call 200 with a fresh SHA.
                probeCount.increment()
                if probeCount.value == 1 {
                    return HTTPResponse(status: 304, headers: [:], body: Data())
                }
                return HTTPResponse(
                    status: 200,
                    headers: ["ETag": "\"etag-\(sha)\""],
                    body: Data((sha + "\n").utf8)
                )
            } else if urlString.contains("tar.gz") {
                let tarData = try makeFakeTarGz(skillName: "zeta", fileContents: "zeta v1")
                return HTTPResponse(status: 200, headers: [:], body: tarData)
            }
            return HTTPResponse(status: 404, headers: [:], body: Data())
        }

        let cacheDir = FileManager.default.temporaryDirectory
            .appending(path: "appcore-everycheck-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cacheDir) }

        let model = AppModel(
            owner: "o", repo: "r", branch: "main",
            transport: transport,
            cacheRoot: cacheDir,
            automaticChecksEnabled: false,   // no timer loop; we drive checks explicitly
            installedSkills: { [:] }         // zeta not installed → .updateAvailable
        )

        // Launch check: 304 → .ok(nil). Observable lastDerivedState must be nil.
        await model.start()
        #expect(model.lastDerivedState == nil,
                "launch check was 304 (unchanged) → lastDerivedState should be nil")

        // Manual trigger (NOT the launch check): 200 → non-nil DerivedState.
        await model.triggerCheck()

        #expect(model.isChecking == false, "isChecking must be false after the manual check completes")
        guard let state = model.lastDerivedState else {
            Issue.record("lastDerivedState must update after a non-launch (manual) check — the bridge synced only once")
            return
        }
        #expect(state.states["zeta"] == .updateAvailable,
                "the observable state must reflect the SECOND check's derived output")
        #expect(state.attention == true)
    }

    @Test @MainActor func observableStateUpdatesOnTimerTick() async throws {
        // BLOCKER 2 (timer path): a timer-loop tick (driven by the deterministic
        // GatedClock) is also a non-launch check and must propagate to the @Observable
        // model. Launch check is 304 (nil); the first timer tick is 200 (non-nil).
        let clock = AppCoreGatedClock()
        let probeCount = CallCounter()
        let sha = "timer-tick-sha"
        let transport = AppCoreStubTransport { url in
            let urlString = url.absoluteString
            if urlString.contains("commits") {
                probeCount.increment()
                if probeCount.value == 1 {
                    return HTTPResponse(status: 304, headers: [:], body: Data())
                }
                return HTTPResponse(
                    status: 200,
                    headers: ["ETag": "\"etag-\(sha)\""],
                    body: Data((sha + "\n").utf8)
                )
            } else if urlString.contains("tar.gz") {
                let tarData = try makeFakeTarGz(skillName: "eta", fileContents: "eta v1")
                return HTTPResponse(status: 200, headers: [:], body: tarData)
            }
            return HTTPResponse(status: 404, headers: [:], body: Data())
        }

        let cacheDir = FileManager.default.temporaryDirectory
            .appending(path: "appcore-timertick-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cacheDir) }

        let model = AppModel(
            owner: "o", repo: "r", branch: "main",
            transport: transport,
            cacheRoot: cacheDir,
            clock: clock,
            interval: 3600,
            automaticChecksEnabled: true,    // timer loop runs
            installedSkills: { [:] }
        )

        // Launch check: 304 → nil. Timer loop then parks in its first sleep.
        await model.start()
        #expect(model.lastDerivedState == nil)

        // Release the timer's first sleep → a non-launch tick fires (200 → non-nil state).
        while clock.sleepCount < 1 { await Task.yield() }
        clock.releaseOne()

        // Wait for the observable model to reflect the tick's result.
        while model.lastDerivedState == nil { await Task.yield() }
        #expect(model.lastDerivedState?.states["eta"] == .updateAvailable,
                "a timer-loop tick must propagate its DerivedState to the @Observable model")
    }

    @Test @MainActor func observableIsCheckingIsFalseAfterCheckCompletes() async throws {
        // After start() returns, the observable isChecking on AppModel is false.
        let transport = AppCoreStubTransport { _ in
            HTTPResponse(status: 304, headers: [:], body: Data())
        }

        let cacheDir = FileManager.default.temporaryDirectory
            .appending(path: "appcore-ischecking-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cacheDir) }

        let model = AppModel(
            owner: "o", repo: "r", branch: "main",
            transport: transport,
            cacheRoot: cacheDir,
            automaticChecksEnabled: false,
            installedSkills: { [:] }
        )

        await model.start()

        #expect(model.isChecking == false)
    }
}

// MARK: — Scheduler: transientError does not clear slow-retry backoff

@Suite("CheckScheduler — transient error handling")
struct SchedulerTransientErrorTests {

    /// A GatedClock that captures sleep durations.
    final class CapturingClock: SchedulerClock, @unchecked Sendable {
        private let lock = NSLock()
        private var _count = 0
        private var _released = 0
        private var _durations: [TimeInterval] = []
        var durations: [TimeInterval] { lock.withLock { _durations } }
        var sleepCount: Int { lock.withLock { _count } }
        func releaseOne() { lock.withLock { _released += 1 } }
        func sleep(for duration: TimeInterval) async throws {
            let idx = lock.withLock { () -> Int in
                _count += 1
                _durations.append(duration)
                return _count
            }
            while lock.withLock({ _released < idx }) && !Task.isCancelled {
                await Task.yield()
            }
        }
    }

    final class CallCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var _value = 0
        var value: Int { lock.withLock { _value } }
        func increment() { lock.withLock { _value += 1 } }
    }

    @Test func transientErrorAfterOriginNotFoundPreservesSlowRetryInterval() async throws {
        // Sequence:
        //   check #1: .originNotFound  → slow-retry engaged
        //   check #2: .transientError  → slow-retry must be PRESERVED (not cleared)
        //   check #3: .ok(nil)         → slow-retry cleared, normal cadence
        //
        // The first sleep after #1 must be slowInterval.
        // The second sleep after #2 must also be slowInterval (not normalInterval).
        // The third sleep after #3 must be normalInterval.

        let clock = CapturingClock()
        let callCount = CallCounter()
        let normalInterval: TimeInterval = 3600
        let slowInterval: TimeInterval = 21600

        let scheduler = CheckScheduler(
            performCheck: {
                callCount.increment()
                switch callCount.value {
                case 1: return .originNotFound
                case 2: return .transientError
                default: return .ok(nil)
                }
            },
            clock: clock,
            interval: normalInterval,
            slowRetryInterval: slowInterval
        )

        // Launch check (#1 → originNotFound). Timer parks in first slow-retry sleep.
        await scheduler.start()
        while clock.sleepCount < 1 { await Task.yield() }
        #expect(clock.durations[0] == slowInterval,
                "First sleep after originNotFound must be slowInterval, got \(clock.durations[0])")

        // Release → check #2 (.transientError). Timer parks in second sleep — must still be slow.
        clock.releaseOne()
        while clock.sleepCount < 2 { await Task.yield() }
        #expect(clock.durations[1] == slowInterval,
                "Second sleep after transientError (following 404) must preserve slowInterval, got \(clock.durations[1])")

        // Release → check #3 (.ok). Timer parks in third sleep — now normal interval.
        clock.releaseOne()
        while clock.sleepCount < 3 { await Task.yield() }
        #expect(clock.durations[2] == normalInterval,
                "Third sleep after ok should restore normalInterval, got \(clock.durations[2])")

        clock.releaseOne()
    }

    @Test func transientErrorDoesNotOverwriteLastDerivedState() async throws {
        // After a successful check that sets lastDerivedState, a subsequent transientError
        // must NOT clear lastDerivedState — the last good state is preserved.
        let expected = DerivedState(states: ["alpha": .updateAvailable], attention: true, selfHealed: [])
        let callCount = CallCounter()

        let scheduler = CheckScheduler(
            performCheck: {
                callCount.increment()
                return callCount.value == 1 ? .ok(expected) : .transientError
            },
            clock: InstantClock(),
            automaticChecksEnabled: false
        )

        await scheduler.start()   // call #1 → .ok(expected)
        let stateAfterSuccess = await scheduler.lastDerivedState
        #expect(stateAfterSuccess == expected)

        await scheduler.triggerCheck()  // call #2 → .transientError
        let stateAfterTransient = await scheduler.lastDerivedState
        #expect(stateAfterTransient == expected,
                "lastDerivedState must be preserved after transientError, got \(String(describing: stateAfterTransient))")
    }
}

// MARK: — Minimal fake tar.gz builder for tests

/// Builds a minimal POSIX tar.gz containing one skill directory with one file.
/// Format: [repo-sha]/skills/[skillName]/SKILL.md (the path TarballExtractor expects)
private func makeFakeTarGz(skillName: String, fileContents: String) throws -> Data {
    // We need a real tar.gz that TarballExtractor can parse.
    // TarballExtractor expects paths like "<prefix>/skills/<name>/<file>".
    // Use a temp directory approach: write files, tar them, read back.
    let tmpDir = FileManager.default.temporaryDirectory
        .appending(path: "faketarball-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let prefix = "repo-abc123"
    let skillDir = tmpDir.appending(path: "\(prefix)/skills/\(skillName)")
    try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
    let skillFile = skillDir.appending(path: "SKILL.md")
    try Data(fileContents.utf8).write(to: skillFile)

    let tarGzPath = tmpDir.appending(path: "archive.tar.gz").path(percentEncoded: false)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
    process.arguments = ["-czf", tarGzPath, "-C", tmpDir.path(percentEncoded: false), prefix]
    try process.run()
    process.waitUntilExit()

    return try Data(contentsOf: URL(fileURLWithPath: tarGzPath))
}

// Reuse InstantClock from SchedulerTests — but it's in a different test target.
// Define a local copy:
private struct InstantClock: SchedulerClock {
    func sleep(for duration: TimeInterval) async throws {}
}
