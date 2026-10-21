import Foundation

/// The kind of server an account signs in to.
public enum ProviderKind: String, Codable, CaseIterable, Hashable, Sendable {
    case github
    case gitlab
    case svn

    /// The name shown to people, e.g. "GitHub".
    public var displayName: String {
        switch self {
        case .github: "GitHub"
        case .gitlab: "GitLab"
        case .svn: "Subversion"
        }
    }

    /// Whether dosc can add accounts of this kind yet.
    public var isAvailable: Bool { self == .github }
}

/// One signed-in account. Holds no secrets: the token lives in the token store, keyed by ``id``.
public struct Account: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let kind: ProviderKind
    /// The web host, e.g. `https://github.com` or a GitHub Enterprise server.
    public let host: URL
    public var login: String
    public var displayName: String?
    public var avatarURL: URL?

    public init(
        id: UUID = UUID(), kind: ProviderKind, host: URL, login: String, displayName: String? = nil,
        avatarURL: URL? = nil
    ) {
        self.id = id
        self.kind = kind
        self.host = host
        self.login = login
        self.displayName = displayName
        self.avatarURL = avatarURL
    }

    /// `login@host` for hosts other than the public one, so two accounts with the same login differ.
    public var label: String {
        let h = host.host() ?? host.absoluteString
        return h == "github.com" || h == "gitlab.com" ? login : "\(login)@\(h)"
    }
}
