import Foundation

/// Facts about how the app was launched, and debug launch arguments for jumping to screens.
///
/// Debug launch arguments (simulator / debug builds only):
/// - `-mockTiles 4`        how many rooms + zones the mock bridge has (default 6)
/// - `-unpaired YES`       start as if no bridge is paired
/// - `-mockOffline YES`    the mock bridge doesn't answer (Bridge not reachable)
/// - `-mockOutsideChanges YES` the mock flips a room every 15 s, like a wall switch
/// - `-mockTemporary YES`  the living room starts with a temporary color
/// - `-realBridge YES`     use the real bridge client even in the simulator
/// - `-openScreen name`    settings, bridge, log, arrange, room, wheel
/// - `-openRoom "Name"`    which room `room`/`wheel` open (default the first)
nonisolated enum RuntimeEnvironment {
    static let arguments = ProcessInfo.processInfo.arguments

    static let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        || arguments.contains("-uiTesting")

    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    /// The simulator can't reach the bridge, so it uses the mock unless told otherwise.
    static var usesMockBridge: Bool {
        if isTesting && !arguments.contains("-uiTesting") { return true }
        return isSimulator && !flag("realBridge")
    }

    /// UI tests (`-uiTesting`) get a blank settings store so earlier runs don't leak in.
    static let sharedStore: SharedStore = {
        guard arguments.contains("-uiTesting"), let blank = UserDefaults(suiteName: "uiTesting") else { return SharedStore() }
        blank.removePersistentDomain(forName: "uiTesting")
        return SharedStore(defaults: blank)
    }()

    static func debugValue(_ key: String) -> String? {
        #if DEBUG
        UserDefaults.standard.string(forKey: key)
        #else
        nil
        #endif
    }

    static func flag(_ key: String) -> Bool { debugValue(key).map { $0 == "YES" || $0 == "1" } ?? false }
}
