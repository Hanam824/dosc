import DoscCore
import Foundation

/// A repository opened recently, for the Home screen.
public struct RecentRepo: Codable, Hashable, Sendable {
    public let accountID: UUID
    public let repo: RepoRef
    public var openedAt: Date

    public init(accountID: UUID, repo: RepoRef, openedAt: Date = .now) {
        self.accountID = accountID
        self.repo = repo
        self.openedAt = openedAt
    }
}

/// Everything dosc remembers except secrets: the accounts (in the order shown) and recent repos.
public struct AppState: Codable, Hashable, Sendable {
    public var accounts: [Account]
    public var recentRepos: [RecentRepo]
    /// Ask for Face ID / the passcode when the app opens.
    public var appLockEnabled: Bool

    public init(accounts: [Account] = [], recentRepos: [RecentRepo] = [], appLockEnabled: Bool = false) {
        self.accounts = accounts
        self.recentRepos = recentRepos
        self.appLockEnabled = appLockEnabled
    }

    /// Moves `repo` to the front of ``recentRepos``, keeping at most `limit`.
    public mutating func noteOpened(_ repo: RepoRef, accountID: UUID, limit: Int = 10) {
        recentRepos.removeAll { $0.accountID == accountID && $0.repo == repo }
        recentRepos.insert(RecentRepo(accountID: accountID, repo: repo), at: 0)
        if recentRepos.count > limit { recentRepos.removeLast(recentRepos.count - limit) }
    }

    /// Removes an account and its recent repos.
    public mutating func removeAccount(_ id: UUID) {
        accounts.removeAll { $0.id == id }
        recentRepos.removeAll { $0.accountID == id }
    }
}

/// Loads and saves ``AppState`` as JSON in Application Support.
public struct AppStateStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// `Application Support/dosc/state.json`.
    public static func standard() -> AppStateStore {
        let dir = URL.applicationSupportDirectory.appending(path: "dosc", directoryHint: .isDirectory)
        return AppStateStore(fileURL: dir.appending(path: "state.json"))
    }

    /// The saved state, or an empty one when nothing is saved or the file can't be read.
    public func load() -> AppState {
        guard let data = try? Data(contentsOf: fileURL) else { return AppState() }
        return (try? JSONDecoder().decode(AppState.self, from: data)) ?? AppState()
    }

    public func save(_ state: AppState) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}
