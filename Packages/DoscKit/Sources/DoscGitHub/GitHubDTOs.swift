import Foundation

// Decodable shapes of the GitHub REST responses dosc reads. Field names are camelCase versions of
// GitHub's snake_case (the decoder converts them); only the fields dosc uses are listed.

struct UserDTO: Decodable {
    let login: String
    let name: String?
    let avatarUrl: URL?
}

struct RepoDTO: Decodable {
    let fullName: String
    let owner: UserDTO
    let description: String?
    let `private`: Bool
    let fork: Bool
    let language: String?
    let stargazersCount: Int?
    let forksCount: Int?
    let openIssuesCount: Int?
    let defaultBranch: String?
    let updatedAt: Date?
    let pushedAt: Date?
    let htmlUrl: URL?
}

struct SearchDTO<Item: Decodable>: Decodable {
    let items: [Item]
}

struct BranchDTO: Decodable {
    struct CommitRef: Decodable { let sha: String }
    let name: String
    let commit: CommitRef?
    let protected: Bool?
}

struct ContentDTO: Decodable {
    let name: String
    let path: String
    let type: String
    let size: Int?
}

struct CommitDTO: Decodable {
    struct GitCommit: Decodable {
        struct Person: Decodable {
            let name: String?
            let email: String?
            let date: Date?
        }
        let message: String
        let author: Person?
    }
    struct Parent: Decodable { let sha: String }
    struct Stats: Decodable {
        let additions: Int
        let deletions: Int
    }

    let sha: String
    let commit: GitCommit
    let author: UserDTO?
    let parents: [Parent]?
    let htmlUrl: URL?
    let stats: Stats?
    let files: [FileDTO]?
}

struct FileDTO: Decodable {
    let filename: String
    let previousFilename: String?
    let status: String
    let additions: Int
    let deletions: Int
    let patch: String?
}

struct LabelDTO: Decodable {
    let name: String
    let color: String?
    let description: String?
}

struct IssueDTO: Decodable {
    struct PullRequestRef: Decodable {
        let mergedAt: Date?
    }

    let number: Int
    let title: String
    let body: String?
    let state: String
    let user: UserDTO?
    let labels: [LabelDTO]?
    let comments: Int?
    let createdAt: Date
    let updatedAt: Date
    let closedAt: Date?
    let htmlUrl: URL?
    /// `https://api.github.com/repos/{owner}/{repo}`; lists across repositories need it.
    let repositoryUrl: URL?
    /// Present when the issue is a pull request.
    let pullRequest: PullRequestRef?
    let draft: Bool?
}

struct PullDTO: Decodable {
    struct BranchRef: Decodable {
        let ref: String
        let label: String?
    }

    let number: Int
    let title: String
    let body: String?
    let state: String
    let user: UserDTO?
    let labels: [LabelDTO]?
    let comments: Int?
    let createdAt: Date
    let updatedAt: Date
    let closedAt: Date?
    let mergedAt: Date?
    let htmlUrl: URL?
    let draft: Bool?
    let head: BranchRef
    let base: BranchRef
    let additions: Int?
    let deletions: Int?
    let changedFiles: Int?
    let commits: Int?
}

struct CommentDTO: Decodable {
    let id: Int
    let user: UserDTO?
    let body: String?
    let createdAt: Date
}

struct NotificationDTO: Decodable {
    struct Subject: Decodable {
        let title: String
        let url: URL?
        let type: String
    }
    struct Repository: Decodable { let fullName: String }

    let id: String
    let unread: Bool
    let reason: String
    let updatedAt: Date
    let subject: Subject
    let repository: Repository
}

struct EventDTO: Decodable {
    struct Actor: Decodable {
        let login: String
        let displayLogin: String?
        let avatarUrl: URL?
    }
    struct Repository: Decodable { let name: String }

    let id: String
    let type: String?
    let actor: Actor
    let repo: Repository
    let payload: JSONValue?
    let createdAt: Date
}

/// Any JSON value, for event payloads whose shape depends on the event type.
enum JSONValue: Decodable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let v = try? c.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? c.decode(Double.self) {
            self = .number(v)
        } else if let v = try? c.decode(String.self) {
            self = .string(v)
        } else if let v = try? c.decode([JSONValue].self) {
            self = .array(v)
        } else {
            self = .object(try c.decode([String: JSONValue].self))
        }
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    var string: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    var int: Int? {
        if case .number(let n) = self { return Int(n) }
        return nil
    }

    var array: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }
}

struct DeviceCodeDTO: Decodable {
    let deviceCode: String
    let userCode: String
    let verificationUri: URL
    let expiresIn: Int
    let interval: Int?
}

struct AccessTokenDTO: Decodable {
    let accessToken: String?
    let error: String?
    let errorDescription: String?
    let interval: Int?
}
