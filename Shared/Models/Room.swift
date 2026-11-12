import Foundation

nonisolated enum RoomKind: String, Codable, Sendable { case room, zone }

/// A Hue room or zone, as one grid tile. It's controlled through its `grouped_light`.
nonisolated struct Room: Codable, Sendable, Hashable, Identifiable {
    var id: String
    var kind: RoomKind
    var name: String
    var archetype: String
    var groupedLightID: String
    var lightIDs: [String]
    var isOn: Bool
    /// 0–100, as the bridge reports it for the grouped light (an average of its bulbs).
    var brightness: Double
    /// What the room's lights show; nil if no bulb reports a color.
    var color: LightColor?
    /// The gamut most of its color bulbs share (nil if none are full color).
    var gamut: Gamut?
    /// The warmth range every bulb in the room supports.
    var mirekRange: ClosedRange<Int>?
    /// The different colors its lights show when they don't all match (a hybrid), up to four.
    /// Nil when they're all one color. Optional so older saved rooms still decode.
    var mixColors: [LightColor]?
    /// True while the bridge is morphing its lights (a moving hybrid).
    var isMoving: Bool?

    var percent: Int { Int(brightness.rounded()) }
    var iconName: String { RoomIcon.symbol(archetype: archetype, kind: kind) }
    var shortName: String { RoomNaming.shortName(name) }
    var supportsColor: Bool { gamut != nil }
    var supportsWarmth: Bool { mirekRange != nil }
    /// The color tiles and swatches show: the room's color, or Hue's warm white.
    var displayColor: LightColor { color ?? .warmWhite }
}

nonisolated enum RoomNaming {
    /// For the widget: drop a trailing "room" ("Living room" → "Living") and keep it short.
    static func shortName(_ name: String, maxLength: Int = 9) -> String {
        var words = name.split(separator: " ").map(String.init)
        if words.count > 1, words.last?.lowercased() == "room" { words.removeLast() }
        let joined = words.joined(separator: " ")
        if joined.count <= maxLength { return joined }
        let first = words.first ?? joined
        return first.count <= maxLength ? first : String(first.prefix(maxLength - 1)) + "…"
    }
}
