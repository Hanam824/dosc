import DoscCore
import Foundation

/// Turns GitHub DTOs into DoscCore models.
enum GitHubMapper {
    static func user(_ dto: UserDTO) -> UserSummary {
        UserSummary(login: dto.login, name: dto.name, avatarURL: dto.avatarUrl)
    }

    static func repo(_ dto: RepoDTO) -> Repo {
        Repo(
            ref: RepoRef(path: dto.fullName),
            owner: user(dto.owner),
            summary: dto.description,
            isPrivate: dto.private,
            isFork: dto.fork,
            language: dto.language,
            stars: dto.stargazersCount ?? 0,
            forks: dto.forksCount ?? 0,
            openIssues: dto.openIssuesCount ?? 0,
            defaultBranch: dto.defaultBranch,
            updatedAt: dto.pushedAt ?? dto.updatedAt,
            webURL: dto.htmlUrl)
    }

    static func branch(_ dto: BranchDTO) -> Branch {
        Branch(name: dto.name, commitID: dto.commit?.sha, isProtected: dto.protected ?? false)
    }

    static func entry(_ dto: ContentDTO) -> FileEntry {
        let kind: FileEntry.Kind =
            switch dto.type {
            case "dir": .directory
            case "symlink": .symlink
            case "submodule": .submodule
            default: .file
            }
        return FileEntry(path: dto.path, name: dto.name, kind: kind, size: dto.size)
    }

    /// Directories first, then files, each sorted by name the way Finder does.
    static func sortEntries(_ entries: [FileEntry]) -> [FileEntry] {
        entries.sorted { a, b in
            let ad = a.kind == .directory
            let bd = b.kind == .directory
            if ad != bd { return ad }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    static func commit(_ dto: CommitDTO) -> Commit {
        let author = dto.commit.author
        return Commit(
            id: dto.sha,
            message: dto.commit.message,
            author: Signature(
                name: author?.name ?? dto.author?.login ?? "Unknown", email: author?.email, date: author?.date),
            authorUser: dto.author.map(user),
            parentIDs: dto.parents?.map(\.sha) ?? [],
            webURL: dto.htmlUrl)
    }

    static func commitDetail(_ dto: CommitDTO) -> CommitDetail {
        let files = (dto.files ?? []).map(fileChange)
        return CommitDetail(
            commit: commit(dto),
            additions: dto.stats?.additions ?? files.reduce(0) { $0 + $1.additions },
            deletions: dto.stats?.deletions ?? files.reduce(0) { $0 + $1.deletions },
            files: files)
    }

    static func fileChange(_ dto: FileDTO) -> FileChange {
        let status: FileChange.Status =
            switch dto.status {
            case "added": .added
            case "removed": .removed
            case "modified", "changed": .modified
            case "renamed", "copied": .renamed
            default: .other
            }
        return FileChange(
            path: dto.filename, previousPath: dto.previousFilename, status: status,
            additions: dto.additions, deletions: dto.deletions, patch: dto.patch)
    }

    static func label(_ dto: LabelDTO) -> Label {
        Label(name: dto.name, color: dto.color ?? "8b949e", summary: dto.description)
    }

    /// `https://api.github.com/repos/{owner}/{repo}` → `owner/repo`.
    static func repoRef(fromAPIURL url: URL) -> RepoRef? {
        let parts = url.pathComponents
        guard let i = parts.lastIndex(of: "repos"), parts.count >= i + 3 else { return nil }
        return RepoRef(owner: parts[i + 1], name: parts[i + 2])
    }

    static func issue(_ dto: IssueDTO, repo: RepoRef?) -> Issue? {
        guard let repo = repo ?? dto.repositoryUrl.flatMap(repoRef(fromAPIURL:)) else { return nil }
        let isPR = dto.pullRequest != nil
        let merged = dto.pullRequest?.mergedAt != nil
        return Issue(
            repo: repo,
            number: dto.number,
            kind: isPR ? .changeRequest : .issue,
            title: dto.title,
            body: dto.body,
            state: merged ? .merged : (dto.state == "open" ? .open : .closed),
            author: dto.user.map(user) ?? UserSummary(login: "ghost"),
            labels: (dto.labels ?? []).map(label),
            commentCount: dto.comments ?? 0,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt,
            closedAt: dto.closedAt,
            webURL: dto.htmlUrl,
            changeRequest: isPR && dto.draft == true
                ? ChangeRequestInfo(sourceBranch: "", targetBranch: "", isDraft: true) : nil)
    }

    static func pull(_ dto: PullDTO, repo: RepoRef) -> Issue {
        Issue(
            repo: repo,
            number: dto.number,
            kind: .changeRequest,
            title: dto.title,
            body: dto.body,
            state: dto.mergedAt != nil ? .merged : (dto.state == "open" ? .open : .closed),
            author: dto.user.map(user) ?? UserSummary(login: "ghost"),
            labels: (dto.labels ?? []).map(label),
            commentCount: dto.comments ?? 0,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt,
            closedAt: dto.closedAt,
            webURL: dto.htmlUrl,
            changeRequest: ChangeRequestInfo(
                sourceBranch: dto.head.label ?? dto.head.ref,
                targetBranch: dto.base.ref,
                isDraft: dto.draft ?? false,
                additions: dto.additions,
                deletions: dto.deletions,
                changedFiles: dto.changedFiles,
                commits: dto.commits,
                mergedAt: dto.mergedAt))
    }

    static func comment(_ dto: CommentDTO) -> Comment {
        Comment(
            id: String(dto.id), author: dto.user.map(user) ?? UserSummary(login: "ghost"),
            body: dto.body ?? "", createdAt: dto.createdAt)
    }

    static func notification(_ dto: NotificationDTO) -> NotificationItem {
        let subject: NotificationItem.Subject =
            switch dto.subject.type {
            case "Issue": .issue
            case "PullRequest": .changeRequest
            case "Commit": .commit
            case "Release": .release
            case "Discussion": .discussion
            case "CheckSuite": .checks
            default: .other
            }
        let number =
            (subject == .issue || subject == .changeRequest)
            ? dto.subject.url.flatMap { Int($0.lastPathComponent) } : nil
        return NotificationItem(
            id: dto.id, title: dto.subject.title, subject: subject, reason: dto.reason,
            repo: RepoRef(path: dto.repository.fullName), isUnread: dto.unread, updatedAt: dto.updatedAt,
            number: number)
    }

    /// Describes an event the way GitHub's feed does; unknown types still show as "acted on".
    static func event(_ dto: EventDTO) -> FeedEvent {
        let p = dto.payload
        let action = p?["action"]?.string
        var kind = FeedEvent.Kind.other
        var summary = "acted on"
        var detail: String?
        var number: Int?

        switch dto.type {
        case "WatchEvent":
            kind = .star
            summary = "starred"
        case "ForkEvent":
            kind = .fork
            summary = "forked"
        case "PushEvent":
            kind = .push
            let ref = (p?["ref"]?.string ?? "").replacingOccurrences(of: "refs/heads/", with: "")
            let commits = p?["commits"]?.array ?? []
            let count = p?["size"]?.int ?? commits.count
            summary = "pushed \(count) commit\(count == 1 ? "" : "s") to \(ref)"
            detail = commits.compactMap { $0["message"]?.string?.split(separator: "\n").first.map(String.init) }
                .prefix(3).joined(separator: "\n")
            if detail?.isEmpty == true { detail = nil }
        case "CreateEvent":
            kind = .create
            let refType = p?["ref_type"]?.string ?? "repository"
            if let ref = p?["ref"]?.string, refType != "repository" {
                summary = "created \(refType) \(ref) in"
            } else {
                summary = "created repository"
            }
        case "DeleteEvent":
            kind = .delete
            summary = "deleted \(p?["ref_type"]?.string ?? "ref") \(p?["ref"]?.string ?? "") in"
        case "IssuesEvent":
            kind = .issue
            number = p?["issue"]?["number"]?.int
            summary = "\(action ?? "updated") issue #\(number ?? 0) in"
            detail = p?["issue"]?["title"]?.string
        case "PullRequestEvent":
            kind = .changeRequest
            number = p?["pull_request"]?["number"]?.int ?? p?["number"]?.int
            let merged = action == "closed" && p?["pull_request"]?["merged"] == .bool(true)
            summary = "\(merged ? "merged" : action ?? "updated") pull request #\(number ?? 0) in"
            detail = p?["pull_request"]?["title"]?.string
        case "IssueCommentEvent", "PullRequestReviewCommentEvent", "CommitCommentEvent":
            kind = .comment
            number = p?["issue"]?["number"]?.int ?? p?["pull_request"]?["number"]?.int
            summary = number.map { "commented on #\($0) in" } ?? "commented in"
            detail = p?["comment"]?["body"]?.string.map { String($0.prefix(200)) }
        case "PullRequestReviewEvent":
            kind = .comment
            number = p?["pull_request"]?["number"]?.int
            summary = "reviewed pull request #\(number ?? 0) in"
        case "ReleaseEvent":
            kind = .release
            let tag = p?["release"]?["tag_name"]?.string ?? ""
            summary = "published release \(tag) of"
        case "MemberEvent":
            kind = .member
            summary = "added \(p?["member"]?["login"]?.string ?? "a member") to"
        case "PublicEvent":
            kind = .publicize
            summary = "made public"
        default:
            break
        }

        return FeedEvent(
            id: dto.id,
            actor: UserSummary(login: dto.actor.displayLogin ?? dto.actor.login, avatarURL: dto.actor.avatarUrl),
            repo: RepoRef(path: dto.repo.name),
            kind: kind,
            summary: summary,
            detail: detail,
            createdAt: dto.createdAt,
            number: number)
    }
}
