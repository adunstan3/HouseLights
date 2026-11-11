import AppIntents

/// Siri phrases. Every phrase has to name the app. A phrase can hold one parameter (the
/// room), so for brightness and warmth Siri asks for the number after the room.
struct HouseLightsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: TurnOffRoomIntent(), phrases: [
            "Turn off the \(\.$room) in \(.applicationName)",
            "Turn off \(\.$room) in \(.applicationName)",
            "Turn off the \(\.$room) with \(.applicationName)",
        ], shortTitle: "Turn Off", systemImageName: "lightbulb.slash")
        AppShortcut(intent: TurnOnRoomIntent(), phrases: [
            "Turn on the \(\.$room) in \(.applicationName)",
            "Turn on \(\.$room) in \(.applicationName)",
            "Turn on the \(\.$room) with \(.applicationName)",
        ], shortTitle: "Turn On", systemImageName: "lightbulb")
        AppShortcut(intent: SetRoomBrightnessIntent(), phrases: [
            "Set the \(\.$room) brightness in \(.applicationName)",
            "Set the \(\.$room) in \(.applicationName)",
            "Dim the \(\.$room) in \(.applicationName)",
        ], shortTitle: "Set Brightness", systemImageName: "sun.max")
        AppShortcut(intent: SetRoomWarmthIntent(), phrases: [
            "Set the \(\.$room) warmth in \(.applicationName)",
        ], shortTitle: "Set Warmth", systemImageName: "thermometer.sun")
    }
}
