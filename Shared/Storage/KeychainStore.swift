import Foundation
import Security

/// The bridge's application key and pinned certificate hash, in the Keychain.
/// Items go in the shared access group so the widget extension can read them; if that
/// group isn't in the entitlements (errSecMissingEntitlement) they're saved app-only.
nonisolated enum KeychainStore {
    static let service = "com.andrewdunstan.HouseLights.bridge"

    enum Account: String {
        case applicationKey = "hue-application-key"
        case certificateHash = "bridge-certificate-sha256"
    }

    @discardableResult
    static func save(_ data: Data, for account: Account) -> OSStatus {
        delete(account)
        var item = baseQuery(account)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        item[kSecAttrAccessGroup as String] = AppGroup.keychainGroup
        var status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecMissingEntitlement {
            item.removeValue(forKey: kSecAttrAccessGroup as String)
            status = SecItemAdd(item as CFDictionary, nil)
        }
        return status
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
    static func saveString(_ value: String, for account: Account) -> OSStatus {
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
