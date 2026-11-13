import Foundation

// Wire formats of the Hue CLIP API v2 (https://<bridge>/clip/v2/resource/<type>).
// Every GET returns `{ "errors": [...], "data": [...] }`. Only the fields the app uses
// are decoded; everything is optional where the bridge may leave it out
// (for example `color` is missing on white-only bulbs).

nonisolated struct HueResponse<Item: Decodable & Sendable>: Decodable, Sendable {
    var errors: [HueAPIError]
    var data: [Item]

    enum CodingKeys: String, CodingKey { case errors, data }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        errors = try c.decodeIfPresent([HueAPIError].self, forKey: .errors) ?? []
        data = try c.decodeIfPresent([Item].self, forKey: .data) ?? []
    }
}

nonisolated struct HueAPIError: Codable, Sendable, Hashable {
    var description: String
}

/// A reference to another resource: `{ "rid": "...", "rtype": "device" }`.
nonisolated struct HueRef: Codable, Sendable, Hashable {
    var rid: String
    var rtype: String
}

nonisolated struct HueMetadata: Codable, Sendable, Hashable {
    var name: String?
    /// Room/zone type such as `living_room`, `kitchen`, `front_door`.
    var archetype: String?
}

nonisolated struct HueOn: Codable, Sendable, Hashable { var on: Bool }
nonisolated struct HueDimming: Codable, Sendable, Hashable {
    /// 0–100. The bridge treats 0 as the bulb's minimum dim level, not off.
    var brightness: Double
}

nonisolated struct HueXY: Codable, Sendable, Hashable { var x: Double; var y: Double }

nonisolated struct HueGamutDTO: Codable, Sendable, Hashable {
    var red: HueXY
    var green: HueXY
    var blue: HueXY
}

nonisolated struct HueColorDTO: Codable, Sendable, Hashable {
    var xy: HueXY
    var gamut: HueGamutDTO?
    var gamut_type: String?
}

nonisolated struct HueMirekSchema: Codable, Sendable, Hashable {
    var mirek_minimum: Int
    var mirek_maximum: Int
}

nonisolated struct HueColorTemperatureDTO: Codable, Sendable, Hashable {
    /// Null while the light is in xy color mode.
    var mirek: Int?
    /// False while the light shows an xy color rather than a white temperature.
    var mirek_valid: Bool?
    var mirek_schema: HueMirekSchema?
}

/// `room` and `zone` resources share this shape. A room's children are *devices*
/// (whose light services we match through `light.owner`); a zone's children are lights.
nonisolated struct HueGroupDTO: Decodable, Sendable {
    var id: String
    var metadata: HueMetadata
    var children: [HueRef]
    var services: [HueRef]
}

nonisolated struct HueGroupedLightDTO: Decodable, Sendable {
    var id: String
    /// `room`, `zone` or `bridge_home` (the all-lights group).
    var owner: HueRef
    var on: HueOn?
    var dimming: HueDimming?
}

nonisolated struct HueLightDTO: Decodable, Sendable {
    var id: String
    /// The device that holds this light service.
    var owner: HueRef
    var metadata: HueMetadata?
    var on: HueOn?
    var dimming: HueDimming?
    var color: HueColorDTO?
    var color_temperature: HueColorTemperatureDTO?
    var dynamics: HueLightDynamics?
}

nonisolated struct HueSceneActionBody: Codable, Sendable, Hashable {
    var on: HueOn?
    var dimming: HueDimming?
    var color: HueSceneColor?
    var color_temperature: HueSceneMirek?
}

nonisolated struct HueSceneColor: Codable, Sendable, Hashable { var xy: HueXY }
nonisolated struct HueSceneMirek: Codable, Sendable, Hashable { var mirek: Int }

nonisolated struct HueSceneAction: Codable, Sendable, Hashable {
    var target: HueRef
    var action: HueSceneActionBody
}

nonisolated struct HueSceneDTO: Decodable, Sendable {
    var id: String
    var metadata: HueMetadata
    /// The room or zone the scene belongs to.
    var group: HueRef
    var actions: [HueSceneAction]
    /// Colors the bridge morphs through when the scene plays dynamically (hybrids).
    var palette: HueScenePalette?
    /// Starts moving whenever the scene is recalled (including from a dimmer switch).
    var auto_dynamic: Bool?
    /// How fast the palette moves, 0–1.
    var speed: Double?
}

/// POST /api pairing reply: an array holding either `success` or `error`.
/// Error type 101 means the link button hasn't been pressed yet.
nonisolated struct HuePairingReply: Decodable, Sendable {
    struct Success: Decodable, Sendable { var username: String; var clientkey: String? }
    struct Failure: Decodable, Sendable { var type: Int; var description: String }
    var success: Success?
    var error: Failure?
}
