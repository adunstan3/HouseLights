import Foundation

/// Sample rooms, zones and colors for the simulator, matching the Rooms grid mockup.
nonisolated enum MockHome {
    private struct Spec {
        var name: String
        var archetype: String
        var on: Bool
        var brightness: Double
        var color: LightColor
        var whiteOnly = false
    }

    private static let specs: [Spec] = [
        Spec(name: "Living room", archetype: "living_room", on: true, brightness: 70, color: .temperature(mirek: 454)),
        Spec(name: "Kitchen", archetype: "kitchen", on: true, brightness: 100, color: .temperature(mirek: 250)),
        Spec(name: "Bedroom", archetype: "bedroom", on: false, brightness: 40, color: .temperature(mirek: 370), whiteOnly: true),
        Spec(name: "Office", archetype: "office", on: true, brightness: 85, color: .xy(XY(x: 0.235, y: 0.235))),
        Spec(name: "Front door", archetype: "front_door", on: false, brightness: 60, color: .temperature(mirek: 370)),
        Spec(name: "Bathroom", archetype: "bathroom", on: true, brightness: 55, color: .temperature(mirek: 200)),
        Spec(name: "Garage", archetype: "garage", on: false, brightness: 100, color: .temperature(mirek: 300)),
        Spec(name: "Garden", archetype: "garden", on: true, brightness: 30, color: .xy(XY(x: 0.3, y: 0.55))),
        Spec(name: "Hallway", archetype: "hallway", on: false, brightness: 50, color: .temperature(mirek: 370)),
        Spec(name: "Dining", archetype: "dining", on: true, brightness: 65, color: .temperature(mirek: 400)),
        Spec(name: "Guest room", archetype: "guest_room", on: false, brightness: 50, color: .temperature(mirek: 370)),
        Spec(name: "Gym", archetype: "gym", on: true, brightness: 90, color: .temperature(mirek: 160)),
        Spec(name: "Laundry", archetype: "laundry_room", on: false, brightness: 80, color: .temperature(mirek: 300)),
        Spec(name: "Porch", archetype: "porch", on: true, brightness: 45, color: .xy(XY(x: 0.55, y: 0.4))),
    ]

    /// `tiles` rooms, plus a Downstairs zone (living room + kitchen lights) that the grid
    /// doesn't show but Siri and the widget can use.
    static func sample(tiles: Int = 6) -> HomeSnapshot {
        var home = HomeSnapshot()
        home.allLightsGroupID = "mock-all"
        let roomSpecs = Array(specs.prefix(max(tiles, 0)))
        for (i, spec) in roomSpecs.enumerated() {
            let lightIDs = ["mock-light-\(i)-a", "mock-light-\(i)-b"]
            for (j, id) in lightIDs.enumerated() {
                home.lights[id] = LightState(
                    id: id, deviceID: "mock-device-\(i)-\(j)", isOn: spec.on, brightness: spec.brightness,
                    color: spec.color, gamut: spec.whiteOnly ? nil : .c, mirekRange: 153...454)
            }
            var room = Room(id: "mock-room-\(i)", kind: .room, name: spec.name, archetype: spec.archetype,
                            groupedLightID: "mock-group-\(i)", lightIDs: lightIDs, isOn: spec.on, brightness: spec.brightness)
            HomeSnapshot.derive(&room, from: lightIDs.compactMap { home.lights[$0] })
            home.rooms.append(room)
        }
        if tiles >= 2 {
            // A zone made of the living room and kitchen lights.
            let ids = ["mock-light-0-a", "mock-light-0-b", "mock-light-1-a", "mock-light-1-b"]
            var zone = Room(id: "mock-zone-0", kind: .zone, name: "Downstairs", archetype: "downstairs",
                            groupedLightID: "mock-group-zone-0", lightIDs: ids, isOn: true, brightness: 80)
            HomeSnapshot.derive(&zone, from: ids.compactMap { home.lights[$0] })
            home.rooms.append(zone)
        }
        // The living room already has a default: warm white at 2700 K.
        if let living = home.rooms.first {
            let lights = home.lights(in: living)
            home.defaults[living.id] = DefaultScene(
                id: "mock-scene-0", roomID: living.id, name: DefaultScene.name(for: living.name),
                actions: DefaultScene.actions(for: lights, color: .temperature(mirek: 370)))
        }
        return home
    }
}
