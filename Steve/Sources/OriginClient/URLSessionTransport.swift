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

        // Convert the header fields dictionary (which may use [String: String]
        // from NSDictionary) to [String: String], defaulting to empty.
        let responseHeaders: [String: String]
        if let allFields = httpResponse.allHeaderFields as? [String: String] {
            responseHeaders = allFields
        } else {
            var converted: [String: String] = [:]
            for (key, value) in httpResponse.allHeaderFields {
                if let k = key as? String, let v = value as? String {
                    converted[k] = v
                }
            }
            responseHeaders = converted
        }

        return HTTPResponse(
            status: httpResponse.statusCode,
            headers: responseHeaders,
            body: data
        )
    }
}
