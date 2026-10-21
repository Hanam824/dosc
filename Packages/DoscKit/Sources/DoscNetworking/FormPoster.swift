import Foundation

/// Sends the `POST`s that OAuth sign-in needs, and nothing else. It's separate from ``HTTPClient``
/// on purpose: only connectors' sign-in code gets one, and it only posts form fields to the
/// endpoints a connector names (e.g. GitHub's device-code and token endpoints), never to an API.
public struct FormPoster: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Posts `fields` form-encoded with `Accept: application/json` and returns the body.
    public func post(_ url: URL, fields: [String: String]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = fields.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((components.percentEncodedQuery ?? "").utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw HTTPError.transport(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw HTTPError.status(status, body: data, headers: [:]) }
        return data
    }
}
