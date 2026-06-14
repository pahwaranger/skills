import Foundation

/// A concrete `HTTPTransport` backed by `URLSession`. This is the live
/// implementation used in production; tests inject a `URLSession` with a
/// `URLProtocol` stub registered so no real network is needed.
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func get(url: URL, headers: [String: String]) async throws -> HTTPResponse {
        var request = URLRequest(url: url)
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        // Build the header dictionary with explicit per-entry string casts rather than
        // `allHeaderFields as? [String: String]`. A whole-dictionary cast fails — and
        // silently drops EVERY header, including the ETag and rate-limit headers
        // OriginClient depends on — if any single key/value doesn't bridge to String.
        // Per-entry casting keeps every well-formed header even if an odd one slips in.
        var responseHeaders: [String: String] = [:]
        for (key, value) in httpResponse.allHeaderFields {
            guard let name = key as? String else { continue }
            if let stringValue = value as? String {
                responseHeaders[name] = stringValue
            } else {
                // Fall back to the case-insensitive accessor for non-String values
                // (e.g. a bridged NSNumber), so the header still survives.
                responseHeaders[name] = httpResponse.value(forHTTPHeaderField: name)
            }
        }

        return HTTPResponse(
            status: httpResponse.statusCode,
            headers: responseHeaders,
            body: data
        )
    }
}
