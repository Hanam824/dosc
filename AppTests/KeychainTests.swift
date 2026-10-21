import DoscStorage
import Foundation
import Testing

/// Runs inside the app, so it catches builds that can't use the Keychain (error -34018 when the
/// app isn't code signed, even on the Simulator).
@Suite struct KeychainTests {
    @Test func storesReadsAndRemovesToken() throws {
        let store = KeychainTokenStore(service: "app.dosc.tests")
        let id = UUID()
        try store.setToken("one", for: id)
        try store.setToken("two", for: id)
        #expect(try store.token(for: id) == "two")
        try store.removeToken(for: id)
        #expect(try store.token(for: id) == nil)
    }
}
