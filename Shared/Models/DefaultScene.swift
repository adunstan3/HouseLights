import Foundation

/// A room's default color, kept on the bridge as a scene named "House Lights – <room>".
/// Scene names are limited to 32 characters, so long room names are shortened. We find
/// the scene by its room plus the "House Lights" prefix, so renaming a room doesn't lose it.
nonisolated struct DefaultScene: Sendable, Hashable, Identifiable {
    var id: String
    var roomID: String
    var name: String
    var actions: [HueSceneAction]

    static let prefix = "House Lights"
    static let maxNameLength = 32

    static func name(for roomName: String) -> String {
        let head = "\(prefix) – "
        let room = String(roomName.prefix(maxNameLength - head.count))
        return head + room
    }

    static func isDefaultScene(_ name: String) -> Bool { name.hasPrefix(prefix) }

    /// The color most of the scene's lights are set to.
    var color: LightColor? {
        let colors = actions.compactMap { a -> LightColor? in
            if let m = a.action.color_temperature?.mirek { return .temperature(mirek: m) }
            if let xy = a.action.color?.xy { return .xy(XY(x: xy.x, y: xy.y)) }
            return nil
        }
        return colors.mostCommon
    }

    /// Scene actions that put every light in the room in `color` at its current brightness.
    static func actions(for lights: [LightState], color: LightColor?) -> [HueSceneAction] {
        lights.map { light in
            var body = HueSceneActionBody(on: HueOn(on: true), dimming: HueDimming(brightness: max(light.brightness, 1)))
            switch color ?? light.color {
            case .temperature(let m)?:
                let clamped = light.mirekRange.map { min(max(m, $0.lowerBound), $0.upperBound) } ?? m
                if light.mirekRange != nil || light.gamut != nil { body.color_temperature = HueSceneMirek(mirek: clamped) }
            case .xy(let p)?:
                if let g = light.gamut { let c = g.clamp(p); body.color = HueSceneColor(xy: HueXY(x: c.x, y: c.y)) }
            case nil:
                break
            }
            return HueSceneAction(target: HueRef(rid: light.id, rtype: "light"), action: body)
        }
    }
}

extension Array where Element: Hashable {
    /// The most frequent element (first seen wins a tie).
    nonisolated var mostCommon: Element? {
        var counts: [Element: Int] = [:]
        for e in self { counts[e, default: 0] += 1 }
        return first { counts[$0] == counts.values.max() }
    }
}
