import Foundation

/// Answers URLSession requests from a handler, so tests never touch the network. Each session
/// gets its own handler (found through a header), so suites can run in parallel.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) -> (Int, [String: String], Data)

    final class Stub: @unchecked Sendable {
        let handler: Handler
        private var recorded: [URLRequest] = []
        private let lock = NSLock()

        init(_ handler: @escaping Handler) { self.handler = handler }
        func record(_ request: URLRequest) { lock.withLock { recorded.append(request) } }
        var requests: [URLRequest] { lock.withLock { recorded } }
    }

    static let header = "X-Stub-ID"
    nonisolated(unsafe) private static var stubs: [String: Stub] = [:]
    private static let lock = NSLock()

    /// A session whose requests go to `handler`, and the stub recording them.
    static func make(_ handler: @escaping Handler) -> (URLSession, Stub) {
        let id = UUID().uuidString
        let stub = Stub(handler)
        lock.withLock { stubs[id] = stub }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        config.httpAdditionalHeaders = [header: id]
        return (URLSession(configuration: config), stub)
    }

    static func session(_ handler: @escaping Handler) -> URLSession { make(handler).0 }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let id = request.value(forHTTPHeaderField: Self.header) ?? ""
        guard let stub = Self.lock.withLock({ Self.stubs[id] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        stub.record(request)
        let (status, headers, data) = stub.handler(request)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
