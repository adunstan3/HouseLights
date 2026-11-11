import AppIntents
import SwiftUI   // brings in the snippet-view result overloads
import Foundation

// Siri and Shortcuts intents. All of them go through RoomActions, so the rules are the
// same as in the app. Each result shows the Siri results snippet (mockups/9-siri-results.png).

struct TurnOnRoomIntent: AppIntent {
    static let title: LocalizedStringResource = "Turn On Room"
    static let description = IntentDescription("Turns on a Hue room or zone.")
    @Parameter(title: "Room") var room: RoomEntity

    init() {}
    init(room: RoomEntity) { self.room = room }

    static var parameterSummary: some ParameterSummary { Summary("Turn on \(\.$room)") }

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let result = try await RoomActions.perform(.on, roomID: room.id)
        return .result(dialog: "\(result.name) is on.", view: RoomSnippetView(room: result, action: .on))
    }
}

struct TurnOffRoomIntent: AppIntent {
    static let title: LocalizedStringResource = "Turn Off Room"
    static let description = IntentDescription("Turns off a Hue room or zone.")
    @Parameter(title: "Room") var room: RoomEntity

    init() {}
    init(room: RoomEntity) { self.room = room }

    static var parameterSummary: some ParameterSummary { Summary("Turn off \(\.$room)") }

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let result = try await RoomActions.perform(.off, roomID: room.id)
        return .result(dialog: "\(result.name) is off.", view: RoomSnippetView(room: result, action: .off))
    }
}

struct SetRoomBrightnessIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Room Brightness"
    static let description = IntentDescription("Sets a Hue room's brightness.")
    @Parameter(title: "Room") var room: RoomEntity
    @Parameter(title: "Brightness", description: "Percent, 1 to 100", inclusiveRange: (1, 100)) var brightness: Int

    init() {}

    static var parameterSummary: some ParameterSummary { Summary("Set \(\.$room) to \(\.$brightness)%") }

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let result = try await RoomActions.perform(.brightness(brightness), roomID: room.id)
        return .result(dialog: "\(result.name) is at \(result.percent)%.", view: RoomSnippetView(room: result, action: .brightness))
    }
}

struct SetRoomWarmthIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Room Warmth"
    static let description = IntentDescription("Sets a Hue room's white color temperature, from 2200 K (warm) to 6500 K (cool).")
    @Parameter(title: "Room") var room: RoomEntity
    @Parameter(title: "Kelvin", inclusiveRange: (2200, 6500)) var kelvin: Int

    init() {}

    static var parameterSummary: some ParameterSummary { Summary("Set \(\.$room) warmth to \(\.$kelvin) K") }

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let result = try await RoomActions.perform(.warmth(kelvin), roomID: room.id)
        return .result(dialog: "\(result.name) is set to \(WarmthScale.label(kelvin)).", view: RoomSnippetView(room: result, action: .warmth))
    }
}

/// The widget's round buttons. Runs without opening the app.
struct ToggleRoomIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Room"
    static let isDiscoverable = false
    @Parameter(title: "Room ID") var roomID: String

    init() {}
    init(roomID: String) { self.roomID = roomID }

    func perform() async throws -> some IntentResult {
        _ = try await RoomActions.perform(.toggle, roomID: roomID)
        return .result()
    }
}
