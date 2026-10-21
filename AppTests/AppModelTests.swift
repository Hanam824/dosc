import DoscCore
import DoscStorage
import Foundation
import Testing

@testable import DoscFeatures

/// A connector that never touches the network.
struct FakeConnector: ProviderConnector {
    var kind: ProviderKind { .github }
    var defaultHost: URL { URL(string: "https://github.com")! }
    func tokenCreationURL(host: URL) -> URL? { nil }
    func signIn(host: URL, token: String) async throws -> Account {
        Account(kind: .github, host: host, login: token)
    }
    func makeProvider(account: Account, token: String) -> any SourceControlProvider {
        FakeProvider(account: account)
    }
}

struct FakeProvider: SourceControlProvider {
    let account: Account
    var capabilities: Set<Capability> { [] }
    func currentUser() async throws -> UserSummary { UserSummary(login: account.login) }
    func repositories(cursor: PageCursor?) async throws -> Page<Repo> { Page(items: []) }
    func repository(_ repo: RepoRef) async throws -> Repo { throw ProviderError.notFound }
    func contents(_ repo: RepoRef, path: String, revision: String?) async throws -> [FileEntry] { [] }
    func file(_ repo: RepoRef, path: String, revision: String?) async throws -> FileContent {
        throw ProviderError.notFound
    }
    func readme(_ repo: RepoRef, revision: String?) async throws -> FileContent? { nil }
    func commits(_ repo: RepoRef, revision: String?, path: String?, cursor: PageCursor?) async throws -> Page<Commit> {
        Page(items: [])
    }
    func commit(_ repo: RepoRef, id: String) async throws -> CommitDetail { throw ProviderError.notFound }
}

@MainActor @Suite struct AppModelTests {
    func makeModel(tokens: InMemoryTokenStore = InMemoryTokenStore()) -> AppModel {
        AppModel(connectors: [FakeConnector()], stateStore: nil, tokenStore: tokens)
    }

    @Test func addingSameLoginReplacesToken() throws {
        let tokens = InMemoryTokenStore()
        let model = makeModel(tokens: tokens)
        let host = URL(string: "https://github.com")!
        try model.addAccount(Account(kind: .github, host: host, login: "a"), token: "t1")
        let id = model.accounts[0].id
        try model.addAccount(Account(kind: .github, host: host, login: "a"), token: "t2")
        #expect(model.accounts.count == 1)
        #expect(model.accounts[0].id == id)
        #expect(try tokens.token(for: id) == "t2")
    }

    @Test func selectionLimitsActiveAccounts() throws {
        let model = makeModel()
        let host = URL(string: "https://github.com")!
        try model.addAccount(Account(kind: .github, host: host, login: "a"), token: "t")
        try model.addAccount(Account(kind: .github, host: host, login: "b"), token: "t")
        #expect(model.activeAccounts.count == 2 && model.showsAccountBadges)
        let b = model.accounts[1]
        model.selection = .account(b.id)
        #expect(model.activeAccounts == [b])
        model.removeAccount(b.id)
        #expect(model.selection == .all)
        #expect(model.provider(for: b.id) == nil)
    }

    @Test func providerNeedsToken() throws {
        let tokens = InMemoryTokenStore()
        let model = makeModel(tokens: tokens)
        try model.addAccount(Account(kind: .github, host: URL(string: "https://github.com")!, login: "a"), token: "t")
        let account = model.accounts[0]
        #expect(model.provider(for: account) != nil)
        try tokens.removeToken(for: account.id)
        let fresh = AppModel(connectors: [FakeConnector()], stateStore: nil, tokenStore: tokens)
        #expect(fresh.provider(for: account) == nil)
    }
}
