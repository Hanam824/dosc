import DoscCore
import DoscNetworking
import Foundation

/// Sends authenticated `GET`s to the GitHub REST API (v3) of one host and decodes the answers.
struct GitHubAPI: Sendable {
    let baseURL: URL
    let token: String
    let http: HTTPClient

    /// `https://api.github.com` for github.com, `https://<host>/api/v3` for GitHub Enterprise Server.
    static func apiBase(for host: URL) -> URL {
        let name = host.host() ?? ""
        if name == "github.com" || name == "www.github.com" { return URL(string: "https://api.github.com")! }
        return host.appending(path: "api/v3")
    }

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Raw file bytes instead of JSON, for the contents and README endpoints.
    static let rawMediaType = "application/vnd.github.raw"

    func url(_ path: String, query: [String: String?] = [:]) -> URL {
        var components = URLComponents(
            url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        let items = query.compactMap { k, v in v.map { URLQueryItem(name: k, value: $0) } }
            .sorted { $0.name < $1.name }
        if !items.isEmpty { components.queryItems = items }
        return components.url!
    }

    /// Sends a `GET` and maps HTTP failures to ``ProviderError``.
    func get(_ url: URL, accept: String = "application/vnd.github+json") async throws -> HTTPResponse {
        let request = HTTPRequest(
            url: url,
            headers: [
                "Authorization": "Bearer \(token)",
                "Accept": accept,
                "X-GitHub-Api-Version": "2022-11-28",
            ])
        do {
            return try await http.send(request)
        } catch let error as HTTPError {
            throw Self.providerError(error)
        }
    }

    func decode<T: Decodable>(_ type: T.Type, _ url: URL) async throws -> T {
        try Self.decode(type, from: try await get(url).data)
    }

    /// One page of a list endpoint, with the `next` link as the cursor.
    func page<DTO: Decodable, Item>(
        _ type: [DTO].Type, _ url: URL, map: (DTO) -> Item?
    ) async throws -> Page<Item> {
        let response = try await get(url)
        let items = try Self.decode(type, from: response.data).compactMap(map)
        return Page(items: items, next: Self.nextCursor(response))
    }

    /// The first page URL, or the URL saved in the cursor for later pages.
    func pageURL(_ cursor: PageCursor?, _ path: String, query: [String: String?] = [:]) -> URL {
        if let cursor, let next = URL(string: cursor.value) { return next }
        var query = query
        if query["per_page"] == nil { query["per_page"] = "30" }
        return url(path, query: query)
    }

    static func nextCursor(_ response: HTTPResponse) -> PageCursor? {
        guard let link = response.header("Link"), let next = LinkHeader.parse(link)["next"] else { return nil }
        return PageCursor(next.absoluteString)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw ProviderError.decoding(String(describing: error))
        }
    }

    static func providerError(_ error: HTTPError) -> ProviderError {
        switch error {
        case .transport(let message):
            return .network(message)
        case .status(let status, let body, let headers):
            let message = (try? decoder.decode(ErrorBody.self, from: body))?.message
            func header(_ name: String) -> String? {
                headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
            }
            switch status {
            case 401: return .unauthorized
            case 404: return .notFound
            case 403, 429:
                if header("X-RateLimit-Remaining") == "0" || status == 429 {
                    let reset = header("X-RateLimit-Reset").flatMap(TimeInterval.init).map(
                        Date.init(timeIntervalSince1970:))
                    return .rateLimited(resetAt: reset)
                }
                return .server(status: status, message: message)
            default:
                return .server(status: status, message: message)
            }
        }
    }

    struct ErrorBody: Decodable { let message: String? }
}
