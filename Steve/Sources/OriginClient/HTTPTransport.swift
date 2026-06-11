import Foundation

/// The single network seam. Everything Steve sends to Origin goes through this;
/// tests stub it and nothing else. A thrown error models a transport-level
/// failure (no connection, timeout); any HTTP status is a returned response.
public protocol HTTPTransport: Sendable {
    func get(url: URL, headers: [String: String]) async throws -> HTTPResponse
}

public struct HTTPResponse: Sendable {
    public let status: Int
    public let headers: [String: String]
    public let body: Data

    public init(status: Int, headers: [String: String], body: Data) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    /// HTTP header names are case-insensitive; servers vary the casing
    /// (`ETag` vs `Etag`), so never index `headers` directly.
    public func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}
