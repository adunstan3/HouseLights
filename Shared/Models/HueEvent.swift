import Foundation

/// One message from GET /eventstream/clip/v2. Each server-sent event's `data:` line is a
/// JSON array of these; `type` is "update", "add", "delete" or "error", and `data` holds
/// partial resources (only the fields that changed, plus `id` and `type`).
nonisolated struct HueEvent: Decodable, Sendable {
    var type: String
    var data: [HueEventItem]
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
}

/// Event color carries only `xy` (no gamut).
nonisolated struct HueEventColor: Decodable, Sendable { var xy: HueXY }
