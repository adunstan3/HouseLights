import Foundation

/// A room's default color, kept on the bridge as a scene named "House Lights – <room>".
/// Scene names are limited to 32 characters, so long room names are shortened. We find
/// the scene by its room plus the "House Lights" prefix, so renaming a room doesn't lose it.
nonisolated struct DefaultScene: Sendable, Hashable, Identifiable {
    var id: String
    var roomID: String
    var name: String
    var actions: [HueSceneAction]
    /// Hybrid scenes: the palette colors and whether the scene starts moving when recalled.
    var palette: [XY] = []
    var autoDynamic = false

    var motion: SceneMotion? {
        palette.count >= 2 ? SceneMotion(colors: palette, brightness: actions.first?.action.dimming?.brightness ?? 100,
                                         moving: autoDynamic) : nil
    }

    /// The different colors its lights are set to (more than one for a hybrid).
    var colors: [LightColor] {
        var out: [LightColor] = []
        for a in actions {
            let c: LightColor? = a.action.color_temperature.map { .temperature(mirek: $0.mirek) }
                ?? a.action.color.map { .xy(XY(x: $0.xy.x, y: $0.xy.y)) }
            if let c, !out.contains(where: { $0.isClose(to: c) }) { out.append(c) }
        }
        return out
    }

    static let prefix = "House Lights"
    static let maxNameLength = 32

    static func name(for roomName: String) -> String {
        let head = "\(prefix) – "
        let room = String(roomName.prefix(maxNameLength - head.count))
        return head + room
    }

    /// A room's default: "House Lights – <room>" (not a "House Lights Now" or "Mix" scene).
    static func isDefaultScene(_ name: String) -> Bool { name.hasPrefix(prefix) && !isRemoteScene(name) && !isMixScene(name) }

    /// The working scene the watch uses to show a hybrid: "House Lights Mix – <room>".
    static let mixPrefix = "House Lights Mix"
    static func mixName(for roomName: String) -> String {
        let head = "\(mixPrefix) – "
        return head + String(roomName.prefix(maxNameLength - head.count))
    }
    static func isMixScene(_ name: String) -> Bool { name.hasPrefix(mixPrefix) }

    /// Per-light actions for a hybrid: each light its own color, all at `brightness`.
    static func actions(for lights: [LightState], assignments: [String: XY], brightness: Double?) -> [HueSceneAction] {
        lights.map { light in
            let level = min(max(brightness ?? light.brightness, 1), 100)
            var body = HueSceneActionBody(on: HueOn(on: true), dimming: HueDimming(brightness: level))
            if let p = assignments[light.id], let g = light.gamut {
                let c = g.clamp(p)
                body.color = HueSceneColor(xy: HueXY(x: c.x, y: c.y))
            }
            return HueSceneAction(target: HueRef(rid: light.id, rtype: "light"), action: body)
        }
    }

    // MARK: Remote scenes

    /// The scene a room's Hue dimmer switch turns the room on with: "House Lights Now – <room>".
    /// The watch rewrites it after every change it makes, so the remote brings back what the
    /// watch last set. The real default stays in the "House Lights – <room>" scene.
    static let remotePrefix = "House Lights Now"

    static func remoteName(for roomName: String) -> String {
        let head = "\(remotePrefix) – "
        return head + String(roomName.prefix(maxNameLength - head.count))
    }

    static func isRemoteScene(_ name: String) -> Bool { name.hasPrefix(remotePrefix) }

    /// The color most of the scene's lights are set to.
    var color: LightColor? {
        let colors = actions.compactMap { a -> LightColor? in
            if let m = a.action.color_temperature?.mirek { return .temperature(mirek: m) }
            if let xy = a.action.color?.xy { return .xy(XY(x: xy.x, y: xy.y)) }
            return nil
        }
        return colors.mostCommon
    }

    /// Scene actions that put every light in the room in `color`, at `brightness` (or each
    /// light's current brightness).
    static func actions(for lights: [LightState], color: LightColor?, brightness: Double? = nil) -> [HueSceneAction] {
        lights.map { light in
            let level = min(max(brightness ?? light.brightness, 1), 100)
            var body = HueSceneActionBody(on: HueOn(on: true), dimming: HueDimming(brightness: level))
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
