import Testing
import Foundation
@testable import OriginClient

// MARK: — URLProtocol stub

/// Thread-safe registry for per-request handlers used by StubURLProtocol.
/// Tests set a handler on entry and clear it on exit.
final class StubHandlerRegistry: @unchecked Sendable {
    static let shared = StubHandlerRegistry()
    private let lock = NSLock()
    private var handler: ((URLRequest) -> Result<(Data, HTTPURLResponse), Error>)?

    func set(_ handler: @escaping (URLRequest) -> Result<(Data, HTTPURLResponse), Error>) {
        lock.withLock { self.handler = handler }
    }

    func clear() {
        lock.withLock { self.handler = nil }
    }

    func handle(_ request: URLRequest) -> Result<(Data, HTTPURLResponse), Error> {
        lock.withLock {
            handler?(request) ?? .failure(URLError(.unknown))
        }
    }
}

/// URLProtocol subclass that routes requests through `StubHandlerRegistry`.
/// Register this class in a URLSessionConfiguration before creating the session.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        switch StubHandlerRegistry.shared.handle(request) {
        case .success(let (data, response)):
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: — Test helpers

/// Create a URLSession that intercepts all requests via `StubURLProtocol`.
private func makeStubSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: config)
}

/// Build an `HTTPURLResponse` with the given status and headers.
private func makeHTTPResponse(url: URL, status: Int, headers: [String: String]) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                    headerFields: headers)!
}

// MARK: — URLSessionTransport tests

/// Tests are serialized because `StubHandlerRegistry.shared` is a global singleton;
/// concurrent tests would race to set/clear the handler.
@Suite(.serialized)
struct URLSessionTransportTests {

    // MARK: — 200 OK maps body + headers

    @Test func status200ReturnedWithBodyAndHeaders() async throws {
        let url = URL(string: "https://api.github.com/test")!
        let body = Data("hello".utf8)

        StubHandlerRegistry.shared.set { req in
            let resp = makeHTTPResponse(url: req.url!, status: 200,
                                        headers: ["ETag": "\"abc\"", "Content-Type": "text/plain"])
            return .success((body, resp))
        }
        defer { StubHandlerRegistry.shared.clear() }

        let transport = URLSessionTransport(session: makeStubSession())
        let response = try await transport.get(url: url, headers: ["X-Test": "1"])

        #expect(response.status == 200)
        #expect(response.body == body)
        #expect(response.header("ETag") == "\"abc\"")
        // Case-insensitive lookup
        #expect(response.header("etag") == "\"abc\"")
    }

    // MARK: — All OriginClient-needed headers survive extraction together

    @Test func responseHeadersOriginClientNeedsAreAllExtracted() async throws {
        // Robustness: ETag AND rate-limit headers must BOTH survive header extraction.
        // The previous `allHeaderFields as? [String:String]` cast would drop ALL headers
        // wholesale if any single key failed to bridge to String. This asserts the headers
        // OriginClient actually reads (ETag, X-RateLimit-Reset) come through intact.
        let url = URL(string: "https://api.github.com/repos/o/r/commits/main")!

        StubHandlerRegistry.shared.set { req in
            let resp = makeHTTPResponse(url: req.url!, status: 200, headers: [
                "ETag": "\"sha-etag\"",
                "X-RateLimit-Reset": "1700000000",
                "X-RateLimit-Remaining": "0",
                "Content-Type": "application/vnd.github.sha",
            ])
            return .success((Data("sha-body".utf8), resp))
        }
        defer { StubHandlerRegistry.shared.clear() }

        let transport = URLSessionTransport(session: makeStubSession())
        let response = try await transport.get(url: url, headers: [:])

        #expect(response.status == 200)
        // ETag is needed for conditional requests; rate-limit for backoff. Both required.
        #expect(response.header("ETag") == "\"sha-etag\"")
        #expect(response.header("X-RateLimit-Reset") == "1700000000")
        // Case-insensitive access still works after extraction.
        #expect(response.header("etag") == "\"sha-etag\"")
        #expect(response.header("x-ratelimit-reset") == "1700000000")
    }

    // MARK: — 304 Not Modified passes through (no body expected)

    @Test func status304ReturnedWithNoBody() async throws {
        let url = URL(string: "https://api.github.com/repos/o/r/commits/main")!

        StubHandlerRegistry.shared.set { req in
            let resp = makeHTTPResponse(url: req.url!, status: 304, headers: [:])
            return .success((Data(), resp))
        }
        defer { StubHandlerRegistry.shared.clear() }

        let transport = URLSessionTransport(session: makeStubSession())
        let response = try await transport.get(url: url, headers: [:])

        #expect(response.status == 304)
        #expect(response.body.isEmpty)
    }

    // MARK: — 403 with rate-limit header passes headers through

    @Test func status403WithRateLimitHeaderPassesThrough() async throws {
        let url = URL(string: "https://api.github.com/repos/o/r/commits/main")!
        let resetEpoch = "1700000000"

        StubHandlerRegistry.shared.set { req in
            let resp = makeHTTPResponse(url: req.url!, status: 403,
                                        headers: ["X-RateLimit-Reset": resetEpoch])
            return .success((Data(), resp))
        }
        defer { StubHandlerRegistry.shared.clear() }

        let transport = URLSessionTransport(session: makeStubSession())
        let response = try await transport.get(url: url, headers: [:])

        #expect(response.status == 403)
        #expect(response.header("X-RateLimit-Reset") == resetEpoch)
    }

    // MARK: — 404 passes through

    @Test func status404PassesThrough() async throws {
        let url = URL(string: "https://api.github.com/repos/o/r/commits/main")!

        StubHandlerRegistry.shared.set { req in
            let resp = makeHTTPResponse(url: req.url!, status: 404, headers: [:])
            return .success((Data(), resp))
        }
        defer { StubHandlerRegistry.shared.clear() }

        let transport = URLSessionTransport(session: makeStubSession())
        let response = try await transport.get(url: url, headers: [:])

        #expect(response.status == 404)
    }

    // MARK: — Transport error throws (network failure)

    @Test func networkErrorThrows() async throws {
        let url = URL(string: "https://api.github.com/repos/o/r/commits/main")!
        let networkError = URLError(.notConnectedToInternet)

        StubHandlerRegistry.shared.set { _ in .failure(networkError) }
        defer { StubHandlerRegistry.shared.clear() }

        let transport = URLSessionTransport(session: makeStubSession())

        await #expect(throws: (any Error).self) {
            _ = try await transport.get(url: url, headers: [:])
        }
    }

    // MARK: — Request headers are forwarded

    @Test func requestHeadersAreForwarded() async throws {
        let url = URL(string: "https://api.github.com/repos/o/r/commits/main")!
        nonisolated(unsafe) var capturedHeaders: [String: String]? = nil

        StubHandlerRegistry.shared.set { req in
            capturedHeaders = req.allHTTPHeaderFields
            let resp = makeHTTPResponse(url: req.url!, status: 200, headers: [:])
            return .success((Data(), resp))
        }
        defer { StubHandlerRegistry.shared.clear() }

        let transport = URLSessionTransport(session: makeStubSession())
        _ = try await transport.get(url: url, headers: [
            "If-None-Match": "\"etag123\"",
            "Accept": "application/vnd.github.sha",
        ])

        #expect(capturedHeaders?["If-None-Match"] == "\"etag123\"")
        #expect(capturedHeaders?["Accept"] == "application/vnd.github.sha")
    }

    // MARK: — Conditional request: If-None-Match header sent when provided

    @Test func conditionalRequestSendsIfNoneMatchHeader() async throws {
        let url = URL(string: "https://api.github.com/repos/o/r/commits/main")!
        nonisolated(unsafe) var receivedETag: String? = nil

        StubHandlerRegistry.shared.set { req in
            receivedETag = req.value(forHTTPHeaderField: "If-None-Match")
            let resp = makeHTTPResponse(url: req.url!, status: 304, headers: [:])
            return .success((Data(), resp))
        }
        defer { StubHandlerRegistry.shared.clear() }

        let transport = URLSessionTransport(session: makeStubSession())
        _ = try await transport.get(url: url, headers: ["If-None-Match": "\"known-etag\""])

        #expect(receivedETag == "\"known-etag\"")
    }
}
