import Foundation
import Testing

@testable import DoscNetworking

@Suite(.serialized) struct HTTPClientTests {
    @Test func onlyReadOnlyMethodsExist() {
        // dosc is read-only: adding a writing method here must be a deliberate, reviewed change.
        #expect(Set(ReadOnlyMethod.allCases.map(\.rawValue)) == ["GET", "HEAD", "PROPFIND", "REPORT"])
    }

    @Test func parsesLinkHeader() {
        let links = LinkHeader.parse(
            #"<https://api.github.com/user/repos?page=2>; rel="next", <https://api.github.com/user/repos?page=5>; rel="last""#
        )
        #expect(links["next"]?.absoluteString == "https://api.github.com/user/repos?page=2")
        #expect(links["last"]?.absoluteString == "https://api.github.com/user/repos?page=5")
        #expect(LinkHeader.parse("garbage").isEmpty)
    }

    @Test func revalidatesWithETag() async throws {
        let (session, stub) = StubProtocol.make { request in
            if request.value(forHTTPHeaderField: "If-None-Match") == "\"v1\"" {
                return (304, [:], Data())
            }
            return (200, ["ETag": "\"v1\"", "X-Test": "1"], Data("first".utf8))
        }
        let client = HTTPClient(session: session)
        let request = HTTPRequest(url: URL(string: "https://example.test/a")!, headers: ["Authorization": "Bearer x"])

        let first = try await client.send(request)
        #expect(String(decoding: first.data, as: UTF8.self) == "first")
        #expect(first.fromCache == false)

        let second = try await client.send(request)
        #expect(String(decoding: second.data, as: UTF8.self) == "first")
        #expect(second.fromCache)
        #expect(second.status == 200)
        #expect(second.header("x-test") == "1")
        #expect(stub.requests.count == 2)
        #expect(stub.requests.allSatisfy { $0.httpMethod == "GET" })
    }

    @Test func otherCredentialsDontShareCache() async throws {
        let session = StubProtocol.session { request in
            #expect(request.value(forHTTPHeaderField: "If-None-Match") == nil)
            return (200, ["ETag": "\"v1\""], Data("x".utf8))
        }
        let client = HTTPClient(session: session)
        let url = URL(string: "https://example.test/b")!
        _ = try await client.send(HTTPRequest(url: url, headers: ["Authorization": "Bearer one"]))
        _ = try await client.send(HTTPRequest(url: url, headers: ["Authorization": "Bearer two"]))
    }

    @Test func throwsStatusErrors() async {
        let session = StubProtocol.session { _ in (404, ["A": "b"], Data("{}".utf8)) }
        let client = HTTPClient(session: session)
        await #expect(throws: HTTPError.status(404, body: Data("{}".utf8), headers: ["A": "b"])) {
            try await client.send(HTTPRequest(url: URL(string: "https://example.test/missing")!))
        }
    }
}
