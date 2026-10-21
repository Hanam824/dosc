import Foundation
import Security

/// Stores one secret (token or password) per account.
public protocol TokenStore: Sendable {
    func token(for accountID: UUID) throws -> String?
    func setToken(_ token: String, for accountID: UUID) throws
    func removeToken(for accountID: UUID) throws
}

public struct KeychainError: LocalizedError, Sendable {
    public let status: OSStatus
    public var errorDescription: String? {
        "Keychain error \(status): \(SecCopyErrorMessageString(status, nil) as String? ?? "unknown")"
    }
}

/// Keeps tokens in the Keychain as generic passwords, readable only on this device after the
/// first unlock (so they aren't in backups restored to other devices).
public struct KeychainTokenStore: TokenStore {
    private let service: String

    public init(service: String = "app.dosc.tokens") {
        self.service = service
    }

    private func query(_ id: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
        ]
    }

    public func token(for accountID: UUID) throws -> String? {
        var q = query(accountID)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw KeychainError(status: status) }
        return String(data: data, encoding: .utf8)
    }

    public func setToken(_ token: String, for accountID: UUID) throws {
        let data = Data(token.utf8)
        let update: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(query(accountID) as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = query(accountID)
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    public func removeToken(for accountID: UUID) throws {
        let status = SecItemDelete(query(accountID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}

/// A ``TokenStore`` in memory, for tests and previews.
public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private var tokens: [UUID: String] = [:]
    private let lock = NSLock()

    public init(_ tokens: [UUID: String] = [:]) { self.tokens = tokens }

    public func token(for accountID: UUID) throws -> String? { lock.withLock { tokens[accountID] } }
    public func setToken(_ token: String, for accountID: UUID) throws { lock.withLock { tokens[accountID] = token } }
    public func removeToken(for accountID: UUID) throws { lock.withLock { tokens[accountID] = nil } }
}
