import DoscCore
import DoscStorage
import Foundation
import Observation

/// Which accounts the tabs show: all of them merged, or one.
public enum AccountSelection: Hashable, Sendable {
    case all
    case account(UUID)
}

/// The app's state: signed-in accounts, the account switcher, recent repositories and the app lock.
/// Screens get providers from here and never see tokens.
@MainActor @Observable
public final class AppModel {
    public private(set) var state: AppState
    public var selection: AccountSelection = .all
    public var isLocked: Bool
    /// The last error saving state, shown in Settings.
    public private(set) var saveError: String?

    @ObservationIgnored let connectors: [ProviderKind: any ProviderConnector]
    @ObservationIgnored private let stateStore: AppStateStore?
    @ObservationIgnored private let tokenStore: any TokenStore
    @ObservationIgnored private var providers: [UUID: any SourceControlProvider] = [:]

    public init(connectors: [any ProviderConnector], stateStore: AppStateStore?, tokenStore: any TokenStore) {
        self.connectors = Dictionary(uniqueKeysWithValues: connectors.map { ($0.kind, $0) })
        self.stateStore = stateStore
        self.tokenStore = tokenStore
        let state = stateStore?.load() ?? AppState()
        self.state = state
        self.isLocked = state.appLockEnabled
    }

    public var accounts: [Account] { state.accounts }

    public func account(_ id: UUID) -> Account? { state.accounts.first { $0.id == id } }

    /// The accounts the current selection covers.
    public var activeAccounts: [Account] {
        switch selection {
        case .all: return state.accounts
        case .account(let id): return state.accounts.filter { $0.id == id }
        }
    }

    /// Whether rows should say which account they come from.
    public var showsAccountBadges: Bool { activeAccounts.count > 1 }

    public func connector(for kind: ProviderKind) -> (any ProviderConnector)? { connectors[kind] }

    /// The provider for an account, or `nil` when its token is missing (e.g. the Keychain was reset).
    public func provider(for account: Account) -> (any SourceControlProvider)? {
        if let cached = providers[account.id] { return cached }
        guard let connector = connectors[account.kind],
            let token = try? tokenStore.token(for: account.id)
        else { return nil }
        let provider = connector.makeProvider(account: account, token: token)
        providers[account.id] = provider
        return provider
    }

    public func provider(for accountID: UUID) -> (any SourceControlProvider)? {
        account(accountID).flatMap(provider(for:))
    }

    /// Adds a signed-in account. Signing in again to the same login on the same host replaces the
    /// old token and keeps the account's place.
    public func addAccount(_ account: Account, token: String) throws {
        var account = account
        if let existing = state.accounts.firstIndex(where: {
            $0.kind == account.kind && $0.host == account.host && $0.login == account.login
        }) {
            account = Account(
                id: state.accounts[existing].id, kind: account.kind, host: account.host, login: account.login,
                displayName: account.displayName, avatarURL: account.avatarURL)
            try tokenStore.setToken(token, for: account.id)
            state.accounts[existing] = account
        } else {
            try tokenStore.setToken(token, for: account.id)
            state.accounts.append(account)
        }
        providers[account.id] = nil
        save()
    }

    /// Signs an account out of dosc: forgets its token and recent repos. Nothing changes on the server.
    public func removeAccount(_ id: UUID) {
        try? tokenStore.removeToken(for: id)
        providers[id] = nil
        state.removeAccount(id)
        if selection == .account(id) { selection = .all }
        save()
    }

    public func moveAccounts(from source: IndexSet, to destination: Int) {
        state.accounts.move(fromOffsets: source, toOffset: destination)
        save()
    }

    public func noteOpened(_ repo: RepoRef, accountID: UUID) {
        state.noteOpened(repo, accountID: accountID)
        save()
    }

    public var appLockEnabled: Bool {
        get { state.appLockEnabled }
        set {
            state.appLockEnabled = newValue
            save()
        }
    }

    private func save() {
        do {
            try stateStore?.save(state)
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }
}
