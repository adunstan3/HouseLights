import Foundation

/// Identifiers shared by the app and the widget extension. Both need the App Groups and
/// Keychain Sharing entitlements with these values (see Config/*.entitlements).
nonisolated enum AppGroup {
    static let id = "group.com.andrewdunstan.HouseLights"
    /// Keychain access group: team prefix + name, matching `$(AppIdentifierPrefix)…` in the entitlements.
    static let keychainGroup = "265N27R6W3.com.andrewdunstan.HouseLights.shared"

    /// Shared UserDefaults; falls back to standard defaults if the group isn't available.
    static var defaults: UserDefaults { UserDefaults(suiteName: id) ?? .standard }

    /// Shared folder for files such as the bridge log.
    static var containerURL: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }
}
