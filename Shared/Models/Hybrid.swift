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
    /// The bridge's dynamic speed, 0–1, for a hybrid saved before speeds could be chosen.
    static let speed = Speed.slow.value

    var colors: [WheelColor]
    var moving: Bool
    /// How fast it moves (nil: saved by an older build, which moved slowly).
    var speed: Speed? = nil

    var pace: Speed { speed ?? .slow }

    /// The Color screen's Slow / Medium / Fast. The bridge takes a speed from 0 to 1; how
    /// fast each feels on real bulbs is a home check.
    enum Speed: String, Codable, CaseIterable, Sendable {
        case slow, medium, fast
        var value: Double {
            switch self {
            case .slow: 0.25
            case .medium: 0.5
            case .fast: 0.8
            }
        }
        var label: String { rawValue.capitalized }
        /// The nearest choice to a scene's stored speed.
        static func nearest(_ v: Double) -> Speed { allCases.min { abs($0.value - v) < abs($1.value - v) }! }
    }

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

    /// The palette as written to the bridge: all four lists, as the bridge itself returns a
    /// scene's palette (the unused ones empty).
    var palette: HueScenePalette {
        HueScenePalette(color: colors.prefix(Hybrid.maxColors).map {
            HueScenePaletteColor(color: HueSceneColor(xy: HueXY(x: $0.x, y: $0.y)),
                                 dimming: HueDimming(brightness: min(max(brightness, 1), 100)))
        }, dimming: [], color_temperature: [], effects: [])
    }
}

/// Scene `palette` (CLIP v2): up to 9 colors, each an xy color with a brightness, plus
/// palette-wide dimming (max 1), color temperatures (max 1) and effects (max 3), which the
/// app leaves empty.
nonisolated struct HueScenePalette: Codable, Sendable, Hashable {
    var color: [HueScenePaletteColor]
    var dimming: [HueDimming]?
    var color_temperature: [HueScenePaletteMirek]?
    var effects: [HueScenePaletteEffect]?
}

nonisolated struct HueScenePaletteMirek: Codable, Sendable, Hashable {
    var color_temperature: HueSceneMirek?
    var dimming: HueDimming?
}

nonisolated struct HueScenePaletteEffect: Codable, Sendable, Hashable {
    var effect: String?
}

nonisolated struct HueScenePaletteColor: Codable, Sendable, Hashable {
    var color: HueSceneColor
    var dimming: HueDimming?
}

/// A light's `dynamics.status`: "dynamic_palette" while a palette is playing, otherwise "none".
nonisolated struct HueLightDynamics: Codable, Sendable, Hashable {
    var status: String?
}
