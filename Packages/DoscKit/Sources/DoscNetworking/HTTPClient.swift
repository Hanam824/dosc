import Foundation

/// The only HTTP methods ``HTTPClient`` can send. dosc never changes anything on a server, so
/// there is no case for POST, PUT, PATCH or DELETE; WebDAV `PROPFIND`/`REPORT` (read-only) are
/// here for Subversion.
public enum ReadOnlyMethod: String, CaseIterable, Sendable {
    case get = "GET"
    case head = "HEAD"
    case propfind = "PROPFIND"
    case report = "REPORT"
}

/// A request ``HTTPClient`` can send.
public struct HTTPRequest: Sendable {
    public var url: URL
    public var method: ReadOnlyMethod
    public var headers: [String: String]
    /// Only `PROPFIND`/`REPORT` carry a body (an XML query); `GET`/`HEAD` never do.
    public var body: Data?

    public init(url: URL, method: ReadOnlyMethod = .get, headers: [String: String] = [:], body: Data? = nil) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }
}

public struct HTTPResponse: Sendable {
    public let data: Data
    public let status: Int
    public let headers: [String: String]
    /// Whether ``data`` came from the ETag cache after a `304 Not Modified`.
    public let fromCache: Bool

    public init(data: Data, status: Int, headers: [String: String], fromCache: Bool = false) {
        self.data = data
        self.status = status
        self.headers = headers
        self.fromCache = fromCache
    }

    /// Looks a header up ignoring case.
    public func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

public enum HTTPError: Error, Sendable, Equatable {
    /// The server answered with a status outside 200–299 (other than a cached 304).
    case status(Int, body: Data, headers: [String: String])
    case transport(String)
}

/// Sends read-only requests. Keeps `ETag`s of successful `GET`s and revalidates with
/// `If-None-Match`, so unchanged lists come back from memory (and, on GitHub, don't count against
/// the rate limit).
public final class HTTPClient: Sendable {
    private let session: URLSession
    private let cache = ETagCache()

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
        for (k, v) in request.headers { urlRequest.setValue(v, forHTTPHeaderField: k) }
        if request.method == .propfind || request.method == .report {
            urlRequest.httpBody = request.body
        }

        // The key includes the headers so two accounts never share entries.
        let key = ETagCache.key(for: request)
        let cached = request.method == .get ? await cache.entry(for: key) : nil
        if let cached { urlRequest.setValue(cached.etag, forHTTPHeaderField: "If-None-Match") }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw HTTPError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw HTTPError.transport("Not an HTTP response") }
        var headers: [String: String] = [:]
        for (k, v) in http.allHeaderFields {
            if let k = k as? String, let v = v as? String { headers[k] = v }
        }

        if http.statusCode == 304, let cached {
            return HTTPResponse(data: cached.data, status: 200, headers: cached.headers, fromCache: true)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw HTTPError.status(http.statusCode, body: data, headers: headers)
        }
        if request.method == .get, let etag = headers.first(where: { $0.key.lowercased() == "etag" })?.value {
            await cache.store(.init(etag: etag, data: data, headers: headers), for: key)
        }
        return HTTPResponse(data: data, status: http.statusCode, headers: headers)
    }

    /// Forgets cached responses, e.g. after an account is removed.
    public func clearCache() async { await cache.removeAll() }
}

actor ETagCache {
    struct Entry: Sendable {
        let etag: String
        let data: Data
        let headers: [String: String]
    }

    private var entries: [String: Entry] = [:]
    private var order: [String] = []
    private let limit = 300

    static func key(for request: HTTPRequest) -> String {
        let headers = request.headers.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        return ([request.url.absoluteString] + headers).joined(separator: "\n")
    }

    func entry(for key: String) -> Entry? { entries[key] }

    func store(_ entry: Entry, for key: String) {
        if entries[key] == nil { order.append(key) }
        entries[key] = entry
        if order.count > limit {
            let old = order.removeFirst()
            entries[old] = nil
        }
    }

    func removeAll() {
        entries = [:]
        order = []
    }
}

/// Parses an RFC 8288 `Link` header, e.g. `<https://…?page=2>; rel="next", <…>; rel="last"`.
public enum LinkHeader {
    public static func parse(_ value: String) -> [String: URL] {
        var links: [String: URL] = [:]
        for part in value.split(separator: ",") {
            let pieces = part.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let first = pieces.first, first.hasPrefix("<"), first.hasSuffix(">"),
                let url = URL(string: String(first.dropFirst().dropLast()))
            else { continue }
            for param in pieces.dropFirst() where param.hasPrefix("rel=") {
                let rels = param.dropFirst(4).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                for rel in rels.split(separator: " ") { links[String(rel)] = url }
            }
        }
        return links
    }
}
