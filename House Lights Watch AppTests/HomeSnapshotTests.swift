import Foundation
import Testing
@testable import House_Lights_Watch_App

/// Builds a home from JSON shaped like the bridge's CLIP v2 replies.
struct HomeSnapshotTests {
    static let rooms = """
    {"errors":[],"data":[
      {"id":"room-1","type":"room","metadata":{"name":"Living room","archetype":"living_room"},
       "children":[{"rid":"dev-1","rtype":"device"},{"rid":"dev-2","rtype":"device"}],
       "services":[{"rid":"gl-1","rtype":"grouped_light"}]},
      {"id":"room-2","type":"room","metadata":{"name":"Empty","archetype":"attic"},"children":[],"services":[]}
    ]}
    """
    static let zones = """
    {"errors":[],"data":[
      {"id":"zone-1","type":"zone","metadata":{"name":"Downstairs","archetype":"downstairs"},
       "children":[{"rid":"light-1","rtype":"light"}],"services":[{"rid":"gl-2","rtype":"grouped_light"}]}
    ]}
    """
    static let groups = """
    {"errors":[],"data":[
      {"id":"gl-1","type":"grouped_light","owner":{"rid":"room-1","rtype":"room"},"on":{"on":true},"dimming":{"brightness":70}},
      {"id":"gl-2","type":"grouped_light","owner":{"rid":"zone-1","rtype":"zone"},"on":{"on":true},"dimming":{"brightness":80}},
      {"id":"gl-all","type":"grouped_light","owner":{"rid":"home-1","rtype":"bridge_home"},"on":{"on":true}}
    ]}
    """
    static let lights = """
    {"errors":[],"data":[
      {"id":"light-1","type":"light","owner":{"rid":"dev-1","rtype":"device"},"metadata":{"name":"Lamp","archetype":"sultan_bulb"},
       "on":{"on":true},"dimming":{"brightness":70,"min_dim_level":0.2},
       "color_temperature":{"mirek":370,"mirek_valid":true,"mirek_schema":{"mirek_minimum":153,"mirek_maximum":500}},
       "color":{"xy":{"x":0.45,"y":0.41},"gamut":{"red":{"x":0.6915,"y":0.3083},"green":{"x":0.17,"y":0.7},"blue":{"x":0.1532,"y":0.0475}},"gamut_type":"C"}},
      {"id":"light-2","type":"light","owner":{"rid":"dev-2","rtype":"device"},"on":{"on":true},"dimming":{"brightness":70},
       "color_temperature":{"mirek":370,"mirek_valid":true,"mirek_schema":{"mirek_minimum":153,"mirek_maximum":454}}}
    ]}
    """
    static let scenes = """
    {"errors":[],"data":[
      {"id":"scene-1","type":"scene","metadata":{"name":"House Lights – Living room"},"group":{"rid":"room-1","rtype":"room"},
       "actions":[{"target":{"rid":"light-1","rtype":"light"},"action":{"on":{"on":true},"color_temperature":{"mirek":370}}}]},
      {"id":"scene-2","type":"scene","metadata":{"name":"Relax"},"group":{"rid":"room-1","rtype":"room"},"actions":[]}
    ]}
    """

    static func home() throws -> HomeSnapshot {
        func d<T: Decodable & Sendable>(_ s: String, _: T.Type) throws -> [T] {
            try JSONDecoder().decode(HueResponse<T>.self, from: Data(s.utf8)).data
        }
        return try HomeSnapshot(rooms: d(rooms, HueGroupDTO.self), zones: d(zones, HueGroupDTO.self),
                                groupedLights: d(groups, HueGroupedLightDTO.self), lights: d(lights, HueLightDTO.self),
                                scenes: d(scenes, HueSceneDTO.self))
    }

    @Test func buildsRoomsAndZonesWithTheirLights() throws {
        let home = try Self.home()
        #expect(home.rooms.map(\.name) == ["Living room", "Downstairs"])   // empty room skipped
        let living = try #require(home.room("room-1"))
        #expect(living.groupedLightID == "gl-1")
        #expect(Set(living.lightIDs) == ["light-1", "light-2"])   // matched through devices
        #expect(living.isOn && living.percent == 70)
        #expect(living.color == .temperature(mirek: 370))
        #expect(living.gamut == .c)
        #expect(living.mirekRange == 153...454)                   // the range both bulbs share
        #expect(living.iconName == "sofa")
        #expect(home.room("zone-1")?.kind == .zone)
        #expect(home.room("zone-1")?.lightIDs == ["light-1"])
        #expect(home.allLightsGroupID == "gl-all")
    }

    @Test func findsOnlyHouseLightsDefaultScenes() throws {
        let home = try Self.home()
        #expect(home.defaults["room-1"]?.id == "scene-1")
        #expect(home.defaults["room-1"]?.color == .temperature(mirek: 370))
        #expect(home.defaults.count == 1)
    }

    @Test func appliesGroupedLightUpdates() throws {
        var home = try Self.home()
        let changed = home.apply(HueEventItem(id: "gl-1", type: "grouped_light", on: HueOn(on: false)))
        #expect(changed == ["room-1"])
        #expect(home.room("room-1")?.isOn == false)
    }

    @Test func appliesLightColorUpdatesToEveryRoomHoldingTheLight() throws {
        var home = try Self.home()
        var item = HueEventItem(id: "light-1", type: "light")
        item.color = HueEventColor(xy: HueXY(x: 0.2, y: 0.2))
        item.color_temperature = HueColorTemperatureDTO(mirek: nil, mirek_valid: false)
        #expect(home.apply(item) == ["room-1", "zone-1"])
        #expect(home.room("zone-1")?.color == .xy(XY(x: 0.2, y: 0.2)))
    }

    @Test func structuralEventsTriggerReload() {
        #expect(HomeSnapshot.needsReload(HueEvent(type: "add", data: [HueEventItem(id: "x", type: "room")])))
        #expect(!HomeSnapshot.needsReload(HueEvent(type: "update", data: [HueEventItem(id: "x", type: "light")])))
        var renamed = HueEventItem(id: "room-1", type: "room")
        renamed.metadata = HueMetadata(name: "Lounge")
        #expect(HomeSnapshot.needsReload(HueEvent(type: "update", data: [renamed])))
    }

    @Test func lightInColorModeReportsXY() {
        let ct = HueColorTemperatureDTO(mirek: nil, mirek_valid: false)
        let color = HueColorDTO(xy: HueXY(x: 0.5, y: 0.4))
        #expect(LightState.color(ct: ct, color: color) == .xy(XY(x: 0.5, y: 0.4)))
        #expect(LightState.color(ct: HueColorTemperatureDTO(mirek: 300, mirek_valid: true), color: color) == .temperature(mirek: 300))
    }
}
