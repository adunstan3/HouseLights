import Foundation

/// A change to a room's `grouped_light`: PUT /clip/v2/resource/grouped_light/<id>.
/// Fields left nil aren't sent. Newer commands merge over older ones so the sender
/// only ever sends the latest value per room.
nonisolated struct GroupedLightCommand: Sendable, Equatable, Encodable {
    var on: Bool?
    var brightness: Double?
    var mirek: Int?
    var xy: XY?

    static func power(_ on: Bool) -> Self { Self(on: on) }

    func merged(with newer: GroupedLightCommand) -> GroupedLightCommand {
        var out = self
        if let on = newer.on { out.on = on }
        if let b = newer.brightness { out.brightness = b }
        if let m = newer.mirek { out.mirek = m; out.xy = nil }
        if let p = newer.xy { out.xy = p; out.mirek = nil }
        // Turning off wins: the bridge refuses brightness and color for lights that are off.
        if newer.on == false { out.brightness = nil; out.mirek = nil; out.xy = nil }
        return out
    }

    private enum Keys: String, CodingKey { case on, dimming, color_temperature, color }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        if let on { try c.encode(HueOn(on: on), forKey: .on) }
        if let brightness {
            // 0 would mean "minimum dim" rather than off, so keep commands in 1...100.
            try c.encode(HueDimming(brightness: min(max(brightness, 1), 100)), forKey: .dimming)
        }
        if let mirek { try c.encode(HueSceneMirek(mirek: mirek), forKey: .color_temperature) }
        if let xy { try c.encode(HueSceneColor(xy: HueXY(x: xy.x, y: xy.y)), forKey: .color) }
    }

    var summary: String {
        var parts: [String] = []
        if let on { parts.append(on ? "on" : "off") }
        if let brightness { parts.append("\(Int(brightness.rounded()))%") }
        if let mirek { parts.append("\(ColorMath.kelvin(fromMirek: mirek))K") }
        if let xy { parts.append(String(format: "xy %.3f,%.3f", xy.x, xy.y)) }
        return parts.joined(separator: " ")
    }
}
