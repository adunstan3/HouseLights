import Foundation
import Security

/// The bridge's application key and pinned certificate hash, in the Keychain.
/// Items go in the shared access group so the widget extension can read them; if that
/// group isn't in the entitlements (errSecMissingEntitlement) they're saved app-only.
nonisolated enum KeychainStore {
    static let service = "com.andrewdunstan.HouseLights.bridge"

    enum Account: String, CaseIterable, Sendable {
        case applicationKey = "hue-application-key"
        case certificateHash = "bridge-certificate-sha256"
    }

    /// Where a save ended up.
    enum SaveResult: Sendable, Equatable {
        /// In the shared access group (the widget can read it).
        case shared
        /// App-only, because the shared group isn't in the entitlements.
        case appOnly
        case failed(OSStatus)

        var succeeded: Bool { if case .failed = self { false } else { true } }
    }

    @discardableResult
    static func save(_ data: Data, for account: Account) -> SaveResult {
        delete(account)
        var item = baseQuery(account)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        item[kSecAttrAccessGroup as String] = AppGroup.keychainGroup
        let status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecSuccess { return .shared }
        guard status == errSecMissingEntitlement else { return .failed(status) }
        item.removeValue(forKey: kSecAttrAccessGroup as String)
        let appOnly = SecItemAdd(item as CFDictionary, nil)
        return appOnly == errSecSuccess ? .appOnly : .failed(appOnly)
    }

    /// Searches every access group the process has, so it finds shared and app-only items.
    static func load(_ account: Account) -> Data? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    static func delete(_ account: Account) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }

    @discardableResult
    static func saveString(_ value: String, for account: Account) -> SaveResult {
        save(Data(value.utf8), for: account)
    }

    static func loadString(_ account: Account) -> String? {
        load(account).flatMap { String(data: $0, encoding: .utf8) }
    }

    private static func baseQuery(_ account: Account) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account.rawValue]
    }
}

/// The Keychain as BridgeCredentials sees it, so tests can use an in-memory one.
nonisolated protocol SecretStore: Sendable {
    func save(_ data: Data, for account: KeychainStore.Account) -> KeychainStore.SaveResult
    func load(_ account: KeychainStore.Account) -> Data?
    func delete(_ account: KeychainStore.Account)
}

/// The real Keychain.
nonisolated struct SystemKeychain: SecretStore {
    func save(_ data: Data, for account: KeychainStore.Account) -> KeychainStore.SaveResult { KeychainStore.save(data, for: account) }
    func load(_ account: KeychainStore.Account) -> Data? { KeychainStore.load(account) }
    func delete(_ account: KeychainStore.Account) { KeychainStore.delete(account) }
}
