import DoscCore
import Foundation
import Testing

@testable import DoscStorage

@Suite struct StorageTests {
    let account = Account(kind: .github, host: URL(string: "https://github.com")!, login: "octo")

    @Test func recentReposMoveToFrontAndAreCapped() {
        var state = AppState(accounts: [account])
        for i in 0..<12 { state.noteOpened(RepoRef(path: "o/r\(i)"), accountID: account.id) }
        state.noteOpened(RepoRef(path: "o/r5"), accountID: account.id)
        #expect(state.recentRepos.count == 10)
        #expect(state.recentRepos.first?.repo.path == "o/r5")
        #expect(state.recentRepos.filter { $0.repo.path == "o/r5" }.count == 1)
    }

    @Test func removingAccountDropsItsRecents() {
        var state = AppState(accounts: [account])
        state.noteOpened(RepoRef(path: "o/r"), accountID: account.id)
        state.removeAccount(account.id)
        #expect(state.accounts.isEmpty)
        #expect(state.recentRepos.isEmpty)
    }

    @Test func savesAndLoadsState() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AppStateStore(fileURL: dir.appending(path: "state.json"))
        #expect(store.load() == AppState())

        var state = AppState(accounts: [account], appLockEnabled: true)
        state.noteOpened(RepoRef(path: "o/r"), accountID: account.id)
        try store.save(state)
        #expect(store.load() == state)
    }

    @Test func inMemoryTokenStore() throws {
        let store = InMemoryTokenStore()
        try store.setToken("t", for: account.id)
        #expect(try store.token(for: account.id) == "t")
        try store.removeToken(for: account.id)
        #expect(try store.token(for: account.id) == nil)
    }
}
