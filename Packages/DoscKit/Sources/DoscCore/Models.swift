import Foundation

/// Identifies a repository on its server: `owner/name` on GitHub, the project path on GitLab,
/// the repository root on Subversion.
public struct RepoRef: Hashable, Codable, Sendable, CustomStringConvertible {
    public let path: String

    public init(path: String) { self.path = path }
    public init(owner: String, name: String) { self.path = "\(owner)/\(name)" }

    /// Everything before the last `/` (empty when there is none).
    public var owner: String {
        guard let i = path.lastIndex(of: "/") else { return "" }
        return String(path[..<i])
    }

    /// The last path component.
    public var name: String {
        guard let i = path.lastIndex(of: "/") else { return path }
        return String(path[path.index(after: i)...])
    }

    public var description: String { path }
}

/// A person or organization as shown next to content.
public struct UserSummary: Hashable, Codable, Sendable {
    public let login: String
    public var name: String?
    public var avatarURL: URL?

    public init(login: String, name: String? = nil, avatarURL: URL? = nil) {
        self.login = login
        self.name = name
        self.avatarURL = avatarURL
    }
}

public struct Repo: Identifiable, Hashable, Sendable {
    public var id: String { ref.path }
    public let ref: RepoRef
    public var owner: UserSummary
    public var summary: String?
    public var isPrivate: Bool
    public var isFork: Bool
    public var language: String?
    public var stars: Int
    public var forks: Int
    public var openIssues: Int
    public var defaultBranch: String?
    public var updatedAt: Date?
    public var webURL: URL?

    public init(
        ref: RepoRef, owner: UserSummary, summary: String? = nil, isPrivate: Bool = false,
        isFork: Bool = false, language: String? = nil, stars: Int = 0, forks: Int = 0,
        openIssues: Int = 0, defaultBranch: String? = nil, updatedAt: Date? = nil, webURL: URL? = nil
    ) {
        self.ref = ref
        self.owner = owner
        self.summary = summary
        self.isPrivate = isPrivate
        self.isFork = isFork
        self.language = language
        self.stars = stars
        self.forks = forks
        self.openIssues = openIssues
        self.defaultBranch = defaultBranch
        self.updatedAt = updatedAt
        self.webURL = webURL
    }
}

public struct Branch: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public var commitID: String?
    public var isProtected: Bool

    public init(name: String, commitID: String? = nil, isProtected: Bool = false) {
        self.name = name
        self.commitID = commitID
        self.isProtected = isProtected
    }
}

/// An entry in a directory listing.
public struct FileEntry: Identifiable, Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable { case file, directory, symlink, submodule }

    public var id: String { path }
    public let path: String
    public let name: String
    public let kind: Kind
    public var size: Int?

    public init(path: String, name: String, kind: Kind, size: Int? = nil) {
        self.path = path
        self.name = name
        self.kind = kind
        self.size = size
    }
}

/// The bytes of one file at one revision.
public struct FileContent: Hashable, Sendable {
    public let path: String
    public let data: Data
    public var webURL: URL?
    /// Where relative links and images in the file point, e.g. the raw directory of a README.
    public var assetBaseURL: URL?

    public init(path: String, data: Data, webURL: URL? = nil, assetBaseURL: URL? = nil) {
        self.path = path
        self.data = data
        self.webURL = webURL
        self.assetBaseURL = assetBaseURL
    }

    public var name: String { path.split(separator: "/").last.map(String.init) ?? path }

    /// Treated as binary when the first 8 KB contain a NUL byte or aren't UTF-8.
    public var isBinary: Bool {
        let head = data.prefix(8000)
        if head.contains(0) { return true }
        return text == nil
    }

    /// The file as UTF-8 text, or `nil` when it isn't valid UTF-8.
    public var text: String? { String(data: data, encoding: .utf8) }

    /// Whether the file looks like an image the app can show.
    public var isImage: Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "gif", "heic", "webp", "bmp", "ico", "tiff"].contains(ext)
    }
}

/// Who made a commit and when.
public struct Signature: Hashable, Sendable {
    public let name: String
    public var email: String?
    public var date: Date?

    public init(name: String, email: String? = nil, date: Date? = nil) {
        self.name = name
        self.email = email
        self.date = date
    }
}

/// A commit (Git) or revision (Subversion).
public struct Commit: Identifiable, Hashable, Sendable {
    /// The full SHA, or the revision number for Subversion.
    public let id: String
    public var message: String
    public var author: Signature
    /// The author's account on the server, when the server knows it.
    public var authorUser: UserSummary?
    public var parentIDs: [String]
    public var webURL: URL?

    public init(
        id: String, message: String, author: Signature, authorUser: UserSummary? = nil,
        parentIDs: [String] = [], webURL: URL? = nil
    ) {
        self.id = id
        self.message = message
        self.author = author
        self.authorUser = authorUser
        self.parentIDs = parentIDs
        self.webURL = webURL
    }

    /// The first line of the message.
    public var title: String {
        message.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? message
    }

    /// The rest of the message after the first line, trimmed; `nil` when there isn't any.
    public var body: String? {
        let parts = message.split(separator: "\n", maxSplits: 1)
        guard parts.count > 1 else { return nil }
        let rest = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? nil : rest
    }

    /// The first 7 characters of a SHA; a revision number as is.
    public var shortID: String { id.count > 12 ? String(id.prefix(7)) : id }
}

/// How one file changed in a commit or change request.
public struct FileChange: Identifiable, Hashable, Sendable {
    public enum Status: String, Hashable, Sendable { case added, modified, removed, renamed, other }

    public var id: String { path }
    public let path: String
    public var previousPath: String?
    public var status: Status
    public var additions: Int
    public var deletions: Int
    /// Unified diff hunks, without the `diff --git`/`---`/`+++` header. `nil` for binary or
    /// very large files.
    public var patch: String?

    public init(
        path: String, previousPath: String? = nil, status: Status, additions: Int = 0,
        deletions: Int = 0, patch: String? = nil
    ) {
        self.path = path
        self.previousPath = previousPath
        self.status = status
        self.additions = additions
        self.deletions = deletions
        self.patch = patch
    }

    /// The parsed ``patch``.
    public var hunks: [DiffHunk] { patch.map(UnifiedDiffParser.parseHunks) ?? [] }
}

public struct CommitDetail: Hashable, Sendable {
    public let commit: Commit
    public var additions: Int
    public var deletions: Int
    public var files: [FileChange]

    public init(commit: Commit, additions: Int, deletions: Int, files: [FileChange]) {
        self.commit = commit
        self.additions = additions
        self.deletions = deletions
        self.files = files
    }
}

public struct Label: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    /// Six hex digits without `#`, e.g. `d73a4a`.
    public var color: String
    public var summary: String?

    public init(name: String, color: String, summary: String? = nil) {
        self.name = name
        self.color = color
        self.summary = summary
    }
}

/// Whether an item is an issue or a change request (GitHub pull request, GitLab merge request).
public enum IssueKind: String, Hashable, Codable, Sendable { case issue, changeRequest }

public enum IssueState: String, Hashable, Codable, Sendable { case open, closed, merged }

/// Extra details only change requests have.
public struct ChangeRequestInfo: Hashable, Sendable {
    public var sourceBranch: String
    public var targetBranch: String
    public var isDraft: Bool
    public var additions: Int?
    public var deletions: Int?
    public var changedFiles: Int?
    public var commits: Int?
    public var mergedAt: Date?

    public init(
        sourceBranch: String, targetBranch: String, isDraft: Bool = false, additions: Int? = nil,
        deletions: Int? = nil, changedFiles: Int? = nil, commits: Int? = nil, mergedAt: Date? = nil
    ) {
        self.sourceBranch = sourceBranch
        self.targetBranch = targetBranch
        self.isDraft = isDraft
        self.additions = additions
        self.deletions = deletions
        self.changedFiles = changedFiles
        self.commits = commits
        self.mergedAt = mergedAt
    }
}

/// An issue or a change request.
public struct Issue: Identifiable, Hashable, Sendable {
    public var id: String { "\(repo.path)#\(number)" }
    public let repo: RepoRef
    public let number: Int
    public var kind: IssueKind
    public var title: String
    public var body: String?
    public var state: IssueState
    public var author: UserSummary
    public var labels: [Label]
    public var commentCount: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var closedAt: Date?
    public var webURL: URL?
    /// Filled in for change requests when loaded on their own (lists may leave it `nil`).
    public var changeRequest: ChangeRequestInfo?

    public init(
        repo: RepoRef, number: Int, kind: IssueKind, title: String, body: String? = nil,
        state: IssueState, author: UserSummary, labels: [Label] = [], commentCount: Int = 0,
        createdAt: Date, updatedAt: Date, closedAt: Date? = nil, webURL: URL? = nil,
        changeRequest: ChangeRequestInfo? = nil
    ) {
        self.repo = repo
        self.number = number
        self.kind = kind
        self.title = title
        self.body = body
        self.state = state
        self.author = author
        self.labels = labels
        self.commentCount = commentCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.closedAt = closedAt
        self.webURL = webURL
        self.changeRequest = changeRequest
    }

    public var isDraft: Bool { changeRequest?.isDraft ?? false }
}

public struct Comment: Identifiable, Hashable, Sendable {
    public let id: String
    public var author: UserSummary
    public var body: String
    public var createdAt: Date

    public init(id: String, author: UserSummary, body: String, createdAt: Date) {
        self.id = id
        self.author = author
        self.body = body
        self.createdAt = createdAt
    }
}

public struct NotificationItem: Identifiable, Hashable, Sendable {
    public enum Subject: String, Hashable, Sendable {
        case issue, changeRequest, commit, release, discussion, checks, other
    }

    public let id: String
    public var title: String
    public var subject: Subject
    /// Why the account got it, e.g. "mention", "review_requested".
    public var reason: String
    public var repo: RepoRef
    public var isUnread: Bool
    public var updatedAt: Date
    /// The issue or change request number, when the subject is one.
    public var number: Int?

    public init(
        id: String, title: String, subject: Subject, reason: String, repo: RepoRef, isUnread: Bool,
        updatedAt: Date, number: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.subject = subject
        self.reason = reason
        self.repo = repo
        self.isUnread = isUnread
        self.updatedAt = updatedAt
        self.number = number
    }
}

/// One entry of the activity feed.
public struct FeedEvent: Identifiable, Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case star, fork, push, create, delete, issue, changeRequest, comment, release, member, publicize,
            other
    }

    public let id: String
    public var actor: UserSummary
    public var repo: RepoRef
    public var kind: Kind
    /// What happened, without the actor, e.g. "starred" or "opened pull request #12".
    public var summary: String
    /// More text when there is some: commit titles, the issue title.
    public var detail: String?
    public var createdAt: Date
    public var number: Int?

    public init(
        id: String, actor: UserSummary, repo: RepoRef, kind: Kind, summary: String,
        detail: String? = nil, createdAt: Date, number: Int? = nil
    ) {
        self.id = id
        self.actor = actor
        self.repo = repo
        self.kind = kind
        self.summary = summary
        self.detail = detail
        self.createdAt = createdAt
        self.number = number
    }
}
