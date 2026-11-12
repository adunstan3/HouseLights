import Foundation

/// A color on the wheel, as hue and saturation, so it fits any room's gamut when applied.
nonisolated struct WheelColor: Codable, Hashable, Sendable {
    var hue: Double
    var saturation: Double

    func xy(in gamut: Gamut?) -> XY { WheelMath.xy(hue: hue, saturation: saturation, gamut: gamut) }
    var rgb: RGB { ColorMath.rgb(hue: hue, saturation: saturation) }
}

/// A hybrid color scheme: several colors spread over a room's bulbs, one color per bulb.
/// When `moving`, the bridge slowly morphs the lights between the colors (a Hue "dynamic
/// scene", played by the bridge, so it keeps going after the watch is put away).
nonisolated struct Hybrid: Codable, Hashable, Sendable {
    /// Hue scene palettes hold at most 9 colors.
    static let maxColors = 9
    /// The bridge's dynamic speed, 0–1; low is a slow morph.
    static let speed = 0.25

    var colors: [WheelColor]
    var moving: Bool

    /// More colors than bulbs can only be shown by moving between them.
    static func mustMove(colors: Int, bulbs: Int) -> Bool { colors > max(bulbs, 1) }

    /// Each bulb gets one color, in turn.
    func assignments(lightIDs: [String], gamut: Gamut?) -> [String: XY] {
        guard !colors.isEmpty else { return [:] }
        var out: [String: XY] = [:]
        for (i, id) in lightIDs.enumerated() { out[id] = colors[i % colors.count].xy(in: gamut) }
        return out
    }
}

/// What a scene needs, beyond its per-light actions, to be a hybrid: the palette the bridge
/// morphs through, and whether it starts moving whenever it's recalled (`auto_dynamic`, which
/// also makes a dimmer switch start it moving).
nonisolated struct SceneMotion: Sendable, Equatable {
    var colors: [XY]
    var brightness: Double
    var moving: Bool
    var speed: Double = Hybrid.speed

    var palette: HueScenePalette {
        HueScenePalette(color: colors.prefix(Hybrid.maxColors).map {
            HueScenePaletteColor(color: HueSceneColor(xy: HueXY(x: $0.x, y: $0.y)),
                                 dimming: HueDimming(brightness: min(max(brightness, 1), 100)))
        })
    }
}

/// Scene `palette` (CLIP v2): up to 9 colors, each an xy color with a brightness.
nonisolated struct HueScenePalette: Codable, Sendable, Hashable {
    var color: [HueScenePaletteColor]
}

nonisolated struct HueScenePaletteColor: Codable, Sendable, Hashable {
    var color: HueSceneColor
    var dimming: HueDimming?
}

/// A light's `dynamics.status`: "dynamic_palette" while a palette is playing, otherwise "none".
nonisolated struct HueLightDynamics: Codable, Sendable, Hashable {
    var status: String?
}
