import Foundation

/// An opaque position in a paged list, handed back by the provider that made it.
public struct PageCursor: Hashable, Sendable {
    public let value: String
    public init(_ value: String) { self.value = value }
}

/// One page of results and the cursor for the next page, `nil` on the last page.
public struct Page<Item: Sendable>: Sendable {
    public var items: [Item]
    public var next: PageCursor?

    public init(items: [Item], next: PageCursor? = nil) {
        self.items = items
        self.next = next
    }
}

/// Features a provider may or may not have. Screens hide what an account's provider lacks.
public enum Capability: String, Hashable, Sendable, CaseIterable {
    case branches, issues, changeRequests, notifications, feed, starred, search
}

/// Which issues or change requests to list.
public struct IssueQuery: Hashable, Sendable {
    public enum Scope: Hashable, Sendable {
        /// Items in one repository.
        case repo(RepoRef)
        /// Items across all repositories that involve the signed-in account.
        case involvingMe
    }

    public var scope: Scope
    public var kind: IssueKind
    /// `.open` or `.closed` (closed includes merged).
    public var state: IssueState

    public init(scope: Scope, kind: IssueKind, state: IssueState = .open) {
        self.scope = scope
        self.kind = kind
        self.state = state
    }
}

/// Errors any provider can throw, so screens can show the same messages for every server.
public enum ProviderError: LocalizedError, Equatable, Sendable {
    /// The token is wrong, expired or revoked.
    case unauthorized
    case notFound
    case rateLimited(resetAt: Date?)
    case unsupported
    case server(status: Int, message: String?)
    case network(String)
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .unauthorized: "The account's token is invalid or expired. Sign in again."
        case .notFound: "Not found, or this account can't see it."
        case .rateLimited(let reset):
            if let reset {
                "Rate limit reached. Try again \(reset.formatted(.relative(presentation: .named)))."
            } else {
                "Rate limit reached. Try again later."
            }
        case .unsupported: "This account's server doesn't support this."
        case .server(let status, let message): message ?? "The server returned an error (\(status))."
        case .network(let message): message
        case .decoding(let message): "Unexpected response from the server: \(message)"
        }
    }
}

/// Read-only access to one account on one server. Implementations exist per ``ProviderKind``;
/// screens only talk to this protocol. Methods for capabilities a provider lacks throw
/// ``ProviderError/unsupported`` (the default implementations below).
public protocol SourceControlProvider: Sendable {
    var account: Account { get }
    var capabilities: Set<Capability> { get }

    func currentUser() async throws -> UserSummary

    /// Repositories the account owns or belongs to, most recently updated first.
    func repositories(cursor: PageCursor?) async throws -> Page<Repo>
    func starredRepositories(cursor: PageCursor?) async throws -> Page<Repo>
    func searchRepositories(query: String, cursor: PageCursor?) async throws -> Page<Repo>
    func repository(_ repo: RepoRef) async throws -> Repo
    func branches(_ repo: RepoRef, cursor: PageCursor?) async throws -> Page<Branch>

    /// Lists a directory. `path` is `""` for the root; `revision` `nil` means the default branch.
    func contents(_ repo: RepoRef, path: String, revision: String?) async throws -> [FileEntry]
    func file(_ repo: RepoRef, path: String, revision: String?) async throws -> FileContent
    /// The README at the root, or `nil` when there is none.
    func readme(_ repo: RepoRef, revision: String?) async throws -> FileContent?

    /// History newest first, optionally only commits touching `path`.
    func commits(_ repo: RepoRef, revision: String?, path: String?, cursor: PageCursor?) async throws -> Page<
        Commit
    >
    func commit(_ repo: RepoRef, id: String) async throws -> CommitDetail

    func issues(_ query: IssueQuery, cursor: PageCursor?) async throws -> Page<Issue>
    /// One issue or change request; change requests come with ``Issue/changeRequest`` filled in.
    func issue(_ repo: RepoRef, number: Int, kind: IssueKind) async throws -> Issue
    func comments(_ repo: RepoRef, number: Int, cursor: PageCursor?) async throws -> Page<Comment>
    func changeRequestFiles(_ repo: RepoRef, number: Int, cursor: PageCursor?) async throws -> Page<FileChange>
    func changeRequestCommits(_ repo: RepoRef, number: Int, cursor: PageCursor?) async throws -> Page<Commit>

    /// Unread notifications, or all recent ones when `includeRead` is set.
    func notifications(includeRead: Bool, cursor: PageCursor?) async throws -> Page<NotificationItem>
    /// Activity from people and repositories the account follows.
    func feed(cursor: PageCursor?) async throws -> Page<FeedEvent>
}

extension SourceControlProvider {
    public func starredRepositories(cursor: PageCursor?) async throws -> Page<Repo> {
        throw ProviderError.unsupported
    }
    public func searchRepositories(query: String, cursor: PageCursor?) async throws -> Page<Repo> {
        throw ProviderError.unsupported
    }
    public func branches(_ repo: RepoRef, cursor: PageCursor?) async throws -> Page<Branch> {
        throw ProviderError.unsupported
    }
    public func issues(_ query: IssueQuery, cursor: PageCursor?) async throws -> Page<Issue> {
        throw ProviderError.unsupported
    }
    public func issue(_ repo: RepoRef, number: Int, kind: IssueKind) async throws -> Issue {
        throw ProviderError.unsupported
    }
    public func comments(_ repo: RepoRef, number: Int, cursor: PageCursor?) async throws -> Page<Comment> {
        throw ProviderError.unsupported
    }
    public func changeRequestFiles(_ repo: RepoRef, number: Int, cursor: PageCursor?) async throws -> Page<
        FileChange
    > {
        throw ProviderError.unsupported
    }
    public func changeRequestCommits(_ repo: RepoRef, number: Int, cursor: PageCursor?) async throws -> Page<
        Commit
    > {
        throw ProviderError.unsupported
    }
    public func notifications(includeRead: Bool, cursor: PageCursor?) async throws -> Page<NotificationItem> {
        throw ProviderError.unsupported
    }
    public func feed(cursor: PageCursor?) async throws -> Page<FeedEvent> {
        throw ProviderError.unsupported
    }
}

/// A code shown to the person during an OAuth device flow.
public struct DeviceCode: Hashable, Sendable {
    public let userCode: String
    public let verificationURL: URL
    public let expiresAt: Date
    /// Seconds to wait between polls.
    public var interval: Int
    /// The provider's secret handle for this sign-in attempt.
    public let deviceCode: String

    public init(userCode: String, verificationURL: URL, expiresAt: Date, interval: Int, deviceCode: String) {
        self.userCode = userCode
        self.verificationURL = verificationURL
        self.expiresAt = expiresAt
        self.interval = interval
        self.deviceCode = deviceCode
    }
}

/// Signs in to a provider, by token or (when supported) by OAuth device flow, and builds providers
/// for signed-in accounts. The app registers one per ``ProviderKind``.
public protocol ProviderConnector: Sendable {
    var kind: ProviderKind { get }
    /// The host used when the person doesn't enter one.
    var defaultHost: URL { get }
    /// Where people create a token, for the sign-in screen.
    func tokenCreationURL(host: URL) -> URL?
    /// Whether ``startDeviceFlow(host:)`` works for `host`.
    func supportsDeviceFlow(host: URL) -> Bool

    /// Checks a token and returns the account it belongs to (with a fresh ``Account/id``).
    func signIn(host: URL, token: String) async throws -> Account
    func startDeviceFlow(host: URL) async throws -> DeviceCode
    /// Polls until the person approves (returns the token), denies or the code expires (throws).
    func finishDeviceFlow(host: URL, code: DeviceCode) async throws -> String

    func makeProvider(account: Account, token: String) -> any SourceControlProvider
}

extension ProviderConnector {
    public func supportsDeviceFlow(host: URL) -> Bool { false }
    public func startDeviceFlow(host: URL) async throws -> DeviceCode { throw ProviderError.unsupported }
    public func finishDeviceFlow(host: URL, code: DeviceCode) async throws -> String {
        throw ProviderError.unsupported
    }
}
