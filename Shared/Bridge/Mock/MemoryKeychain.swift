import Foundation
import Security
import Synchronization

/// An in-memory stand-in for the Keychain (simulator mock bridge and tests). `failing`
/// makes saves to those accounts fail, to test what pairing does then.
nonisolated final class MemoryKeychain: SecretStore {
    private let items = Mutex<[KeychainStore.Account: Data]>([:])
    private let failures: Mutex<Set<KeychainStore.Account>>

    init(failing: Set<KeychainStore.Account> = []) { failures = Mutex(failing) }

    func save(_ data: Data, for account: KeychainStore.Account) -> KeychainStore.SaveResult {
        if failures.withLock({ $0.contains(account) }) { return .failed(errSecIO) }
        items.withLock { $0[account] = data }
        return .shared
    }

    func load(_ account: KeychainStore.Account) -> Data? { items.withLock { $0[account] } }
    func delete(_ account: KeychainStore.Account) { _ = items.withLock { $0.removeValue(forKey: account) } }
}
