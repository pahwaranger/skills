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

        // On Apple platforms allHeaderFields is typed [AnyHashable: Any] but
        // always contains [String: String] values in practice. The `as? [String: String]`
        // cast succeeds unconditionally here; the else branch is unreachable and removed.
        let responseHeaders = (httpResponse.allHeaderFields as? [String: String]) ?? [:]

        return HTTPResponse(
            status: httpResponse.statusCode,
            headers: responseHeaders,
            body: data
        )
    }
}
