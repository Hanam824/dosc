import DoscCore
import DoscNetworking
import Foundation
import Testing

@testable import DoscGitHub

func fixture(_ name: String) -> Data {
    let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
    return try! Data(contentsOf: url)
}

let githubAccount = Account(kind: .github, host: URL(string: "https://github.com")!, login: "octocat")

@Suite struct GitHubMapperTests {
    @Test func mapsRepositories() throws {
        let repos = try GitHubAPI.decode([RepoDTO].self, from: fixture("repos")).map(GitHubMapper.repo)
        #expect(repos.count == 2)
        #expect(repos[0].ref == RepoRef(owner: "octocat", name: "Hello-World"))
        #expect(repos[0].stars == 2800 && repos[0].language == "Swift" && repos[0].defaultBranch == "master")
        #expect(repos[0].updatedAt == ISO8601DateFormatter().date(from: "2026-10-02T11:00:00Z"))
        #expect(repos[1].isPrivate && repos[1].isFork && repos[1].summary == nil)
    }

    @Test func sortsDirectoriesFirst() throws {
        let entries = try GitHubAPI.decode([ContentDTO].self, from: fixture("contents")).map(GitHubMapper.entry)
        let sorted = GitHubMapper.sortEntries(entries)
        #expect(sorted.map(\.name) == ["Docs", "src", "a.txt", "README.md", "Vendor"])
        #expect(sorted.last?.kind == .submodule)
    }

    @Test func mapsCommitDetail() throws {
        let detail = GitHubMapper.commitDetail(try GitHubAPI.decode(CommitDTO.self, from: fixture("commit")))
        #expect(detail.commit.title == "Fix all the bugs")
        #expect(detail.commit.body == "And add tests.")
        #expect(detail.commit.author.name == "Monalisa Octocat")
        #expect(detail.commit.authorUser?.login == "octocat")
        #expect(detail.additions == 104 && detail.deletions == 4)
        #expect(detail.files.map(\.status) == [.modified, .renamed, .removed])
        #expect(detail.files[1].previousPath == "old/name.png" && detail.files[1].patch == nil)
        #expect(detail.files[0].hunks.first?.lines.count == 4)
    }

    @Test func mapsSearchIssuesAcrossHosts() throws {
        let items = try GitHubAPI.decode(SearchDTO<IssueDTO>.self, from: fixture("search_issues")).items
            .compactMap { GitHubMapper.issue($0, repo: nil) }
        #expect(items.count == 2)
        #expect(items[0].repo.path == "apple/swift")
        #expect(items[0].kind == .changeRequest && items[0].state == .merged)
        #expect(items[1].repo.path == "team/app")
        #expect(items[1].isDraft && items[1].state == .open)
    }

    @Test func mapsPullRequest() throws {
        let pr = GitHubMapper.pull(
            try GitHubAPI.decode(PullDTO.self, from: fixture("pull")), repo: RepoRef(path: "o/r"))
        #expect(pr.kind == .changeRequest && pr.state == .open && pr.isDraft)
        #expect(pr.changeRequest?.sourceBranch == "octocat:new-topic")
        #expect(pr.changeRequest?.targetBranch == "master")
        #expect(pr.changeRequest?.changedFiles == 5)
    }

    @Test func mapsNotifications() throws {
        let items = try GitHubAPI.decode([NotificationDTO].self, from: fixture("notifications"))
            .map(GitHubMapper.notification)
        #expect(items[0].subject == .changeRequest && items[0].number == 123 && items[0].isUnread)
        #expect(items[1].subject == .release && items[1].number == nil)
    }

    @Test func describesEvents() throws {
        let events = try GitHubAPI.decode([EventDTO].self, from: fixture("events")).map(GitHubMapper.event)
        #expect(events[0].kind == .star && events[0].summary == "starred")
        #expect(events[1].summary == "pushed 2 commits to main")
        #expect(events[1].detail == "First\nSecond")
        #expect(events[2].summary == "merged pull request #7 in" && events[2].number == 7)
        #expect(events[2].detail == "Add thing")
        #expect(events[3].kind == .other)
    }

    @Test func apiBaseForEnterprise() {
        #expect(GitHubAPI.apiBase(for: URL(string: "https://github.com")!).absoluteString == "https://api.github.com")
        #expect(
            GitHubAPI.apiBase(for: URL(string: "https://git.corp.example")!).absoluteString
                == "https://git.corp.example/api/v3")
    }
}

@Suite(.serialized) struct GitHubProviderTests {
    func provider(_ handler: @escaping StubProtocol.Handler) -> GitHubProvider {
        GitHubProvider(account: githubAccount, token: "tok", http: HTTPClient(session: StubProtocol.session(handler)))
    }

    func recordingProvider(_ handler: @escaping StubProtocol.Handler) -> (GitHubProvider, StubProtocol.Stub) {
        let (session, stub) = StubProtocol.make(handler)
        return (GitHubProvider(account: githubAccount, token: "tok", http: HTTPClient(session: session)), stub)
    }

    @Test func pagesWithLinkHeaderAndSendsAuth() async throws {
        let (p, stub) = recordingProvider({ request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
            #expect(request.httpMethod == "GET")
            if request.url!.query()?.contains("page=2") == true { return (200, [:], Data("[]".utf8)) }
            return (
                200, ["Link": "<https://api.github.com/user/repos?page=2&per_page=30&sort=pushed>; rel=\"next\""],
                fixture("repos")
            )
        })
        let first = try await p.repositories(cursor: nil)
        #expect(first.items.count == 2)
        let next = try #require(first.next)
        let second = try await p.repositories(cursor: next)
        #expect(second.items.isEmpty && second.next == nil)
        #expect(stub.requests.first?.url?.path() == "/user/repos")
    }

    @Test func repoIssuesDropPullRequests() async throws {
        let p = provider { request in
            #expect(request.url!.path() == "/repos/octocat/Hello-World/issues")
            #expect(request.url!.query()?.contains("state=closed") == true)
            return (200, [:], fixture("repo_issues"))
        }
        let page = try await p.issues(
            IssueQuery(scope: .repo(RepoRef(path: "octocat/Hello-World")), kind: .issue, state: .closed), cursor: nil)
        #expect(page.items.map(\.number) == [1347])
        #expect(page.items[0].labels.first?.name == "bug")
    }

    @Test func involvingMeUsesSearch() async throws {
        let p = provider { request in
            let q = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
                .first { $0.name == "q" }?.value
            #expect(q == "is:pr is:open involves:octocat archived:false")
            return (200, [:], fixture("search_issues"))
        }
        let page = try await p.issues(IssueQuery(scope: .involvingMe, kind: .changeRequest), cursor: nil)
        #expect(page.items.count == 2)
    }

    @Test func fileRequestsRawContentAtRevision() async throws {
        let p = provider { request in
            #expect(request.value(forHTTPHeaderField: "Accept") == GitHubAPI.rawMediaType)
            #expect(request.url!.path() == "/repos/o/r/contents/dir/My%20File.swift")
            #expect(request.url!.query() == "ref=dev")
            return (200, [:], Data("let x = 1".utf8))
        }
        let file = try await p.file(RepoRef(path: "o/r"), path: "dir/My File.swift", revision: "dev")
        #expect(file.text == "let x = 1")
        #expect(file.name == "My File.swift")
    }

    @Test func encodesSpecialCharactersInPaths() async throws {
        let p = provider { request in
            #expect(request.url!.absoluteString.hasPrefix("https://api.github.com/repos/o/r/contents/a%23b%3Fc.txt"))
            return (200, [:], Data())
        }
        _ = try await p.file(RepoRef(path: "o/r"), path: "a#b?c.txt", revision: nil)
    }

    @Test func missingReadmeIsNil() async throws {
        let p = provider { _ in (404, [:], Data(#"{"message":"Not Found"}"#.utf8)) }
        #expect(try await p.readme(RepoRef(path: "o/r"), revision: nil) == nil)
    }

    @Test func mapsAuthAndRateLimitErrors() async {
        let unauthorized = provider { _ in (401, [:], Data(#"{"message":"Bad credentials"}"#.utf8)) }
        await #expect(throws: ProviderError.unauthorized) { try await unauthorized.currentUser() }

        let limited = provider { _ in
            (403, ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "1800000000"], Data("{}".utf8))
        }
        await #expect(throws: ProviderError.rateLimited(resetAt: Date(timeIntervalSince1970: 1_800_000_000))) {
            try await limited.currentUser()
        }

        let forbidden = provider { _ in (403, [:], Data(#"{"message":"Resource not accessible"}"#.utf8)) }
        await #expect(throws: ProviderError.server(status: 403, message: "Resource not accessible")) {
            try await forbidden.currentUser()
        }
    }
}

@Suite(.serialized) struct GitHubConnectorTests {
    @Test func signInReturnsAccountForToken() async throws {
        let session = StubProtocol.session { request in
            #expect(request.url!.absoluteString == "https://api.github.com/user")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc")
            return (200, [:], fixture("user"))
        }
        let connector = GitHubConnector(clientID: nil, http: HTTPClient(session: session))
        let account = try await connector.signIn(host: connector.defaultHost, token: "  abc\n")
        #expect(account.login == "octocat" && account.displayName == "The Octocat")
        #expect(account.kind == .github)
    }

    @Test func deviceFlowNeedsClientIDAndGitHubDotCom() {
        let http = HTTPClient()
        #expect(
            !GitHubConnector(clientID: nil, http: http).supportsDeviceFlow(host: URL(string: "https://github.com")!))
        #expect(!GitHubConnector(clientID: "", http: http).supportsDeviceFlow(host: URL(string: "https://github.com")!))
        let c = GitHubConnector(clientID: "Iv1.x", http: http)
        #expect(c.supportsDeviceFlow(host: URL(string: "https://github.com")!))
        #expect(!c.supportsDeviceFlow(host: URL(string: "https://ghe.example")!))
    }

    @Test func deviceFlowPollsUntilApproved() async throws {
        let polls = Counter()
        let session = StubProtocol.session { request in
            #expect(request.httpMethod == "POST")
            if request.url!.path() == "/login/device/code" {
                return (
                    200, [:],
                    Data(
                        #"{"device_code":"dc","user_code":"ABCD-1234","verification_uri":"https://github.com/login/device","expires_in":900,"interval":5}"#
                            .utf8)
                )
            }
            switch polls.increment() {
            case 1: return (200, [:], Data(#"{"error":"authorization_pending"}"#.utf8))
            case 2: return (200, [:], Data(#"{"error":"slow_down","interval":10}"#.utf8))
            default: return (200, [:], Data(#"{"access_token":"gho_token","token_type":"bearer"}"#.utf8))
            }
        }
        let slept = Recorder()
        let connector = GitHubConnector(
            clientID: "Iv1.x", http: HTTPClient(session: session), poster: FormPoster(session: session),
            sleep: { slept.append($0) })
        let host = URL(string: "https://github.com")!
        let code = try await connector.startDeviceFlow(host: host)
        #expect(code.userCode == "ABCD-1234" && code.interval == 5)
        let token = try await connector.finishDeviceFlow(host: host, code: code)
        #expect(token == "gho_token")
        #expect(slept.values == [.seconds(5), .seconds(5), .seconds(10)])
    }

    @Test func deviceFlowDenied() async throws {
        let session = StubProtocol.session { _ in (200, [:], Data(#"{"error":"access_denied"}"#.utf8)) }
        let connector = GitHubConnector(
            clientID: "Iv1.x", http: HTTPClient(session: session), poster: FormPoster(session: session), sleep: { _ in }
        )
        let code = DeviceCode(
            userCode: "X", verificationURL: URL(string: "https://github.com/login/device")!,
            expiresAt: .now.addingTimeInterval(60), interval: 1, deviceCode: "dc")
        await #expect(throws: DeviceFlowError.denied) {
            try await connector.finishDeviceFlow(host: URL(string: "https://github.com")!, code: code)
        }
    }
}

final class Counter: @unchecked Sendable {
    private var value = 0
    private let lock = NSLock()
    func increment() -> Int {
        lock.withLock {
            value += 1; return value
        }
    }
}

final class Recorder: @unchecked Sendable {
    private var stored: [Duration] = []
    private let lock = NSLock()
    func append(_ d: Duration) { lock.withLock { stored.append(d) } }
    var values: [Duration] { lock.withLock { stored } }
}
