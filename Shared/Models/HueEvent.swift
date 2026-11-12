import Foundation

/// One message from GET /eventstream/clip/v2. Each server-sent event's `data:` line is a
/// JSON array of these; `type` is "update", "add", "delete" or "error", and `data` holds
/// partial resources (only the fields that changed, plus `id` and `type`).
///
/// Decoding is deliberately lenient: the stream carries every kind of resource (buttons,
/// motion sensors, zigbee status…), so an item we can't read, or a field in an unexpected
/// shape, is skipped on its own instead of losing the whole batch.
nonisolated struct HueEvent: Decodable, Sendable {
    var type: String
    var data: [HueEventItem]

    init(type: String, data: [HueEventItem]) {
        self.type = type
        self.data = data
    }

    private enum Keys: String, CodingKey { case type, data }
    private struct Skip: Decodable { init(from decoder: any Decoder) {} }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        type = (try? c.decode(String.self, forKey: .type)) ?? "unknown"
        var items: [HueEventItem] = []
        if var list = try? c.nestedUnkeyedContainer(forKey: .data) {
            while !list.isAtEnd {
                if let item = try? list.decode(HueEventItem.self) { items.append(item) }
                else { _ = try? list.decode(Skip.self) }
            }
        }
        data = items
    }
}

nonisolated struct HueEventItem: Decodable, Sendable {
    var id: String
    var type: String
    var owner: HueRef?
    var on: HueOn?
    var dimming: HueDimming?
    var color: HueEventColor?
    var color_temperature: HueColorTemperatureDTO?
    var metadata: HueMetadata?
    var dynamics: HueLightDynamics?

    init(id: String, type: String, owner: HueRef? = nil, on: HueOn? = nil, dimming: HueDimming? = nil,
         color: HueEventColor? = nil, color_temperature: HueColorTemperatureDTO? = nil, metadata: HueMetadata? = nil,
         dynamics: HueLightDynamics? = nil) {
        self.id = id; self.type = type; self.owner = owner; self.on = on; self.dimming = dimming
        self.color = color; self.color_temperature = color_temperature; self.metadata = metadata
        self.dynamics = dynamics
    }

    private enum Keys: String, CodingKey { case id, type, owner, on, dimming, color, color_temperature, metadata, dynamics }

    /// Only `id` and `type` are required; every other field is read on its own.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = try c.decode(String.self, forKey: .id)
        type = try c.decode(String.self, forKey: .type)
        owner = try? c.decodeIfPresent(HueRef.self, forKey: .owner)
        on = try? c.decodeIfPresent(HueOn.self, forKey: .on)
        dimming = try? c.decodeIfPresent(HueDimming.self, forKey: .dimming)
        color = try? c.decodeIfPresent(HueEventColor.self, forKey: .color)
        color_temperature = try? c.decodeIfPresent(HueColorTemperatureDTO.self, forKey: .color_temperature)
        metadata = try? c.decodeIfPresent(HueMetadata.self, forKey: .metadata)
        dynamics = try? c.decodeIfPresent(HueLightDynamics.self, forKey: .dynamics)
    }
}

/// Event color carries only `xy` (no gamut).
nonisolated struct HueEventColor: Decodable, Sendable { var xy: HueXY }
