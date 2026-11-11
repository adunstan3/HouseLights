import Foundation

/// One bulb's state, from a `light` resource.
nonisolated struct LightState: Codable, Sendable, Hashable, Identifiable {
    var id: String
    /// The device that holds this light. Rooms list devices, not lights.
    var deviceID: String
    var isOn: Bool
    var brightness: Double
    /// Nil for white-only bulbs with no color temperature.
    var color: LightColor?
    /// Nil for bulbs without full color.
    var gamut: Gamut?
    /// Mirek range the bulb supports, for clamping warmth.
    var mirekRange: ClosedRange<Int>?

    init(id: String, deviceID: String, isOn: Bool, brightness: Double, color: LightColor?,
         gamut: Gamut?, mirekRange: ClosedRange<Int>?) {
        self.id = id; self.deviceID = deviceID; self.isOn = isOn; self.brightness = brightness
        self.color = color; self.gamut = gamut; self.mirekRange = mirekRange
    }

    init(_ dto: HueLightDTO) {
        id = dto.id
        deviceID = dto.owner.rid
        isOn = dto.on?.on ?? false
        brightness = dto.dimming?.brightness ?? 100
        color = LightState.color(ct: dto.color_temperature, color: dto.color)
        gamut = dto.color?.gamut.map(Gamut.init) ?? (dto.color == nil ? nil : .c)
        if let s = dto.color_temperature?.mirek_schema { mirekRange = s.mirek_minimum...s.mirek_maximum }
    }

    /// Hue v2 has no explicit color mode: a light showing white has a valid mirek,
    /// one showing an xy color has `mirek_valid: false` (and often `mirek: null`).
    static func color(ct: HueColorTemperatureDTO?, color: HueColorDTO?) -> LightColor? {
        if let ct, let m = ct.mirek, ct.mirek_valid ?? true { return .temperature(mirek: m) }
        if let color { return .xy(XY(x: color.xy.x, y: color.xy.y)) }
        if let m = ct?.mirek { return .temperature(mirek: m) }
        return nil
    }
}
