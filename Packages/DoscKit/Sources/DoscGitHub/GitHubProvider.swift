import DoscCore
import DoscNetworking
import Foundation

/// Read-only access to one GitHub (or GitHub Enterprise Server) account through the REST API.
public struct GitHubProvider: SourceControlProvider {
    public let account: Account
    let api: GitHubAPI

    public init(account: Account, token: String, http: HTTPClient) {
        self.account = account
        self.api = GitHubAPI(baseURL: GitHubAPI.apiBase(for: account.host), token: token, http: http)
    }

    public var capabilities: Set<Capability> { Set(Capability.allCases) }

    private func repoPath(_ repo: RepoRef, _ rest: String = "") -> String {
        "repos/\(repo.path)\(rest)"
    }

    public func currentUser() async throws -> UserSummary {
        GitHubMapper.user(try await api.decode(UserDTO.self, api.url("user")))
    }

    // MARK: Repositories

    public func repositories(cursor: PageCursor?) async throws -> Page<Repo> {
        let url = api.pageURL(cursor, "user/repos", query: ["sort": "pushed"])
        return try await api.page([RepoDTO].self, url, map: GitHubMapper.repo)
    }

    public func starredRepositories(cursor: PageCursor?) async throws -> Page<Repo> {
        let url = api.pageURL(cursor, "user/starred")
        return try await api.page([RepoDTO].self, url, map: GitHubMapper.repo)
    }

    public func searchRepositories(query: String, cursor: PageCursor?) async throws -> Page<Repo> {
        let url = api.pageURL(cursor, "search/repositories", query: ["q": query])
        let response = try await api.get(url)
        let result = try GitHubAPI.decode(SearchDTO<RepoDTO>.self, from: response.data)
        return Page(items: result.items.map(GitHubMapper.repo), next: GitHubAPI.nextCursor(response))
    }

    public func repository(_ repo: RepoRef) async throws -> Repo {
        GitHubMapper.repo(try await api.decode(RepoDTO.self, api.url(repoPath(repo))))
    }

    public func branches(_ repo: RepoRef, cursor: PageCursor?) async throws -> Page<Branch> {
        let url = api.pageURL(cursor, repoPath(repo, "/branches"), query: ["per_page": "100"])
        return try await api.page([BranchDTO].self, url, map: GitHubMapper.branch)
    }

    // MARK: Code

    public func contents(_ repo: RepoRef, path: String, revision: String?) async throws -> [FileEntry] {
        let url = api.url(repoPath(repo, "/contents/\(path)"), query: ["ref": revision])
        let entries = try await api.decode([ContentDTO].self, url).map(GitHubMapper.entry)
        return GitHubMapper.sortEntries(entries)
    }

    public func file(_ repo: RepoRef, path: String, revision: String?) async throws -> FileContent {
        let url = api.url(repoPath(repo, "/contents/\(path)"), query: ["ref": revision])
        let data = try await api.get(url, accept: GitHubAPI.rawMediaType).data
        let web = account.host.appending(path: "\(repo.path)/blob/\(revision ?? "HEAD")/\(path)")
        return FileContent(path: path, data: data, webURL: web)
    }

    public func readme(_ repo: RepoRef, revision: String?) async throws -> FileContent? {
        let url = api.url(repoPath(repo, "/readme"), query: ["ref": revision])
        do {
            let data = try await api.get(url, accept: GitHubAPI.rawMediaType).data
            return FileContent(path: "README.md", data: data, assetBaseURL: rawBaseURL(repo, revision: revision))
        } catch ProviderError.notFound {
            return nil
        }
    }

    /// Where raw files of `repo` are served, for relative images in READMEs. Private repositories'
    /// images need a token, so they don't load there.
    func rawBaseURL(_ repo: RepoRef, revision: String?) -> URL {
        let rev = revision ?? "HEAD"
        if account.host.host() == "github.com" {
            return URL(string: "https://raw.githubusercontent.com/")!.appending(path: "\(repo.path)/\(rev)/")
        }
        return account.host.appending(path: "\(repo.path)/raw/\(rev)/")
    }

    // MARK: History

    public func commits(_ repo: RepoRef, revision: String?, path: String?, cursor: PageCursor?) async throws
        -> Page<Commit>
    {
        let url = api.pageURL(cursor, repoPath(repo, "/commits"), query: ["sha": revision, "path": path])
        return try await api.page([CommitDTO].self, url, map: GitHubMapper.commit)
    }

    public func commit(_ repo: RepoRef, id: String) async throws -> CommitDetail {
        let url = api.url(repoPath(repo, "/commits/\(id)"))
        return GitHubMapper.commitDetail(try await api.decode(CommitDTO.self, url))
    }

    // MARK: Issues and pull requests

    public func issues(_ query: IssueQuery, cursor: PageCursor?) async throws -> Page<Issue> {
        switch query.scope {
        case .repo(let repo):
            let state = query.state == .open ? "open" : "closed"
            if query.kind == .changeRequest {
                let url = api.pageURL(
                    cursor, repoPath(repo, "/pulls"), query: ["state": state, "sort": "updated", "direction": "desc"])
                return try await api.page([PullDTO].self, url) { GitHubMapper.pull($0, repo: repo) }
            }
            // The issues endpoint also returns pull requests; drop them.
            let url = api.pageURL(cursor, repoPath(repo, "/issues"), query: ["state": state])
            return try await api.page([IssueDTO].self, url) { dto in
                dto.pullRequest == nil ? GitHubMapper.issue(dto, repo: repo) : nil
            }
        case .involvingMe:
            let type = query.kind == .changeRequest ? "is:pr" : "is:issue"
            let state = query.state == .open ? "is:open" : "is:closed"
            let q = "\(type) \(state) involves:\(account.login) archived:false"
            let url = api.pageURL(cursor, "search/issues", query: ["q": q, "sort": "updated"])
            let response = try await api.get(url)
            let result = try GitHubAPI.decode(SearchDTO<IssueDTO>.self, from: response.data)
            return Page(
                items: result.items.compactMap { GitHubMapper.issue($0, repo: nil) },
                next: GitHubAPI.nextCursor(response))
        }
    }

    public func issue(_ repo: RepoRef, number: Int, kind: IssueKind) async throws -> Issue {
        if kind == .changeRequest {
            let url = api.url(repoPath(repo, "/pulls/\(number)"))
            return GitHubMapper.pull(try await api.decode(PullDTO.self, url), repo: repo)
        }
        let url = api.url(repoPath(repo, "/issues/\(number)"))
        guard let issue = GitHubMapper.issue(try await api.decode(IssueDTO.self, url), repo: repo) else {
            throw ProviderError.notFound
        }
        return issue
    }

    public func comments(_ repo: RepoRef, number: Int, cursor: PageCursor?) async throws -> Page<Comment> {
        let url = api.pageURL(cursor, repoPath(repo, "/issues/\(number)/comments"), query: ["per_page": "50"])
        return try await api.page([CommentDTO].self, url, map: GitHubMapper.comment)
    }

    public func changeRequestFiles(_ repo: RepoRef, number: Int, cursor: PageCursor?) async throws -> Page<
        FileChange
    > {
        let url = api.pageURL(cursor, repoPath(repo, "/pulls/\(number)/files"), query: ["per_page": "50"])
        return try await api.page([FileDTO].self, url, map: GitHubMapper.fileChange)
    }

    public func changeRequestCommits(_ repo: RepoRef, number: Int, cursor: PageCursor?) async throws -> Page<
        Commit
    > {
        let url = api.pageURL(cursor, repoPath(repo, "/pulls/\(number)/commits"), query: ["per_page": "50"])
        return try await api.page([CommitDTO].self, url, map: GitHubMapper.commit)
    }

    // MARK: Inbox

    public func notifications(includeRead: Bool, cursor: PageCursor?) async throws -> Page<NotificationItem> {
        let url = api.pageURL(cursor, "notifications", query: ["all": includeRead ? "true" : "false"])
        return try await api.page([NotificationDTO].self, url, map: GitHubMapper.notification)
    }

    public func feed(cursor: PageCursor?) async throws -> Page<FeedEvent> {
        let url = api.pageURL(cursor, "users/\(account.login)/received_events")
        return try await api.page([EventDTO].self, url, map: GitHubMapper.event)
    }
}
