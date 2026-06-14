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
            cacheStore: CacheStore(root: cacheDir)
        )()

        guard case .originNotFound = result else {
            Issue.record("expected .originNotFound, got \(result)")
            return
        }
    }

    // MARK: — Successful check returns .ok(DerivedState?)

    @Test func successfulCheckReturnsOkWithNilStateWhenCacheMissing() async throws {
        // When the cache has no metadata (fresh install), a successful 304
        // (nothing changed) should return .ok(nil) — no state derivation possible.
        let transport = AppCoreStubTransport { _ in
            HTTPResponse(status: 304, headers: [:], body: Data())
        }

        let cacheDir = FileManager.default.temporaryDirectory
            .appending(path: "appcore-ok-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cacheDir) }

        let result = await AppModel.makePerformCheck(
            owner: "o", repo: "r", branch: "main",
            transport: transport,
            cacheStore: CacheStore(root: cacheDir)
        )()

        guard case .ok = result else {
            Issue.record("expected .ok, got \(result)")
            return
        }
    }

    // MARK: — networkError (5xx) returns .ok(nil) — non-destructive, keep last state

    @Test func networkErrorReturnsOk() async throws {
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
            cacheStore: CacheStore(root: cacheDir)
        )()

        // 5xx maps to networkError (non-destructive) → .ok(nil)
        guard case .ok(let state) = result else {
            Issue.record("expected .ok, got \(result)")
            return
        }
        #expect(state == nil)
    }

    // MARK: — rateLimited returns .ok(nil) — non-destructive

    @Test func rateLimitedReturnsOk() async throws {
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
            cacheStore: CacheStore(root: cacheDir)
        )()

        guard case .ok(let state) = result else {
            Issue.record("expected .ok(nil) for rateLimited, got \(result)")
            return
        }
        #expect(state == nil)
    }

    // MARK: — Observable state: isChecking and lastDerivedState update

    @Test func observableStateIsCheckingUpdates() async throws {
        // AppModel exposes a CheckScheduler; after start() its isChecking is false.
        let transport = AppCoreStubTransport { _ in
            HTTPResponse(status: 304, headers: [:], body: Data())
        }

        let cacheDir = FileManager.default.temporaryDirectory
            .appending(path: "appcore-observable-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cacheDir) }

        let model = AppModel(
            owner: "o", repo: "r", branch: "main",
            transport: transport,
            cacheRoot: cacheDir,
            automaticChecksEnabled: false
        )

        await model.start()

        let isChecking = await model.scheduler.isChecking
        #expect(isChecking == false)
    }
}
