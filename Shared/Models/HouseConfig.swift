import Foundation

/// A saved whole-house configuration (grid › bookmark): how every room shown on the grid
/// looked when it was saved, light by light, so loading it brings the house back exactly.
/// Kept on the watch only.
nonisolated struct HouseConfig: Codable, Sendable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var savedAt: Date
    var rooms: [RoomConfig]

    /// Names are trimmed and kept short enough for a watch row.
    static func cleanName(_ text: String) -> String? {
        let name = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        return name.isEmpty ? nil : name
    }
}

/// One room in a configuration.
nonisolated struct RoomConfig: Codable, Sendable, Equatable {
    var roomID: String
    var roomName: String
    var isOn: Bool
    /// Every light in the room: on or off, brightness and color.
    var lights: [LightSetting]
    /// The hybrid the app was showing there, if any (its colors, moving, speed).
    var hybrid: Hybrid?
    /// The room's temporary color, if it wasn't showing its default.
    var temporary: LightColor?
}

nonisolated struct LightSetting: Codable, Sendable, Equatable {
    var id: String
    var isOn: Bool
    var brightness: Double
    var color: LightColor?

    init(_ light: LightState) {
        id = light.id; isOn = light.isOn; brightness = light.brightness; color = light.color
    }

    /// The scene action that puts this light back: off, or on at its brightness and color.
    func sceneAction(for light: LightState) -> HueSceneAction {
        guard isOn else {
            return HueSceneAction(target: HueRef(rid: id, rtype: "light"), action: HueSceneActionBody(on: HueOn(on: false)))
        }
        var current = light
        current.brightness = brightness
        current.color = color
        return DefaultScene.actions(for: [current], color: nil)[0]
    }
}
