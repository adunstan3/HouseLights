import Foundation
import Testing
import UIKit
@testable import House_Lights_Watch_App

struct NamingAndStorageTests {
    @Test func widgetShortNames() {
        #expect(RoomNaming.shortName("Living room") == "Living")
        #expect(RoomNaming.shortName("Bedroom") == "Bedroom")
        #expect(RoomNaming.shortName("Porch") == "Porch")
        #expect(RoomNaming.shortName("Room") == "Room")
        #expect(RoomNaming.shortName("Guest room") == "Guest")
        #expect(RoomNaming.shortName("Downstairs hallway") == "Downstai…")
    }

    @Test func defaultSceneNamesFitHuesLimit() {
        #expect(DefaultScene.name(for: "Kitchen") == "House Lights – Kitchen")
        let long = DefaultScene.name(for: "The very long downstairs living room")
        #expect(long.count <= 32)
        #expect(DefaultScene.isDefaultScene(long))
    }

    /// The "–" is 3 bytes in UTF-8, so names are fitted to 32 bytes, not 32 characters.
    @Test func sceneNamesFitInThirtyTwoBytes() {
        for room in ["Master bedroom", "The very long downstairs living room", "Den"] {
            for name in [DefaultScene.name(for: room), DefaultScene.mixName(for: room), DefaultScene.remoteName(for: room)] {
                #expect(name.utf8.count <= 32, "\(name)")
            }
        }
        #expect(DefaultScene.mixName(for: "Den") == "House Lights Mix – Den")
        #expect(DefaultScene.isMixScene(DefaultScene.mixName(for: "Master bedroom")))
    }

    /// A hybrid's palette goes out with all four lists, as the bridge returns them.
    @Test func paletteIsWrittenWithAllFourLists() throws {
        let motion = SceneMotion(colors: [XY(x: 0.6, y: 0.3), XY(x: 0.2, y: 0.1)], brightness: 80, moving: true)
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(motion.palette)) as? [String: Any])
        #expect(Set(json.keys) == ["color", "dimming", "color_temperature", "effects"])
        #expect((json["color"] as? [Any])?.count == 2)
        #expect((json["effects"] as? [Any])?.isEmpty == true)
    }

    @Test func everyArchetypeIconExists() {
        for name in Set(RoomIcon.symbols.values) + [RoomIcon.fallback, "house"] {
            #expect(UIImage(systemName: name) != nil, "missing SF Symbol \(name)")
        }
        #expect(RoomIcon.symbol(archetype: "kitchen", kind: .room) == "frying.pan")
        #expect(RoomIcon.symbol(archetype: "other", kind: .room) == "lightbulb")
        #expect(RoomIcon.symbol(archetype: "other", kind: .zone) == "house")
    }

    @Test func gridOrderAppendsNewRooms() {
        func room(_ id: String) -> Room {
            Room(id: id, kind: .room, name: id, archetype: "other", groupedLightID: "g\(id)", lightIDs: [], isOn: false, brightness: 0)
        }
        let rooms = ["a", "b", "c", "d"].map(room)
        #expect(GridOrder.apply(["c", "a", "gone"], to: rooms).map(\.id) == ["c", "a", "b", "d"])
        #expect(GridOrder.apply([], to: rooms).map(\.id) == ["a", "b", "c", "d"])
    }

    @Test func sharedStoreRoundTrips() throws {
        let defaults = try #require(UserDefaults(suiteName: "test-\(UUID())"))
        let store = SharedStore(defaults: defaults)
        store.temporaryRooms = ["r1": .temperature(mirek: 300)]
        store.zeroDimmed = ["r2"]
        #expect(store.temporaryRooms["r1"] == .temperature(mirek: 300))
        #expect(store.zeroDimmed == ["r2"])
        store.lastKnownRooms = MockHome.sample().rooms
        #expect(store.lastKnownRooms.count == 7)
    }

    @Test func mockSampleMatchesTheMockup() {
        let home = MockHome.sample()
        #expect(home.rooms.map(\.name) == ["Living room", "Kitchen", "Bedroom", "Office", "Front door", "Bathroom", "Downstairs"])
        #expect(home.rooms.last?.kind == .zone)
        #expect(MockHome.sample(tiles: 4).rooms.filter { $0.kind == .room }.count == 4)
        #expect(MockHome.sample(tiles: 12).rooms.filter { $0.kind == .room }.count == 12)
    }

    @Test func mockBridgeAppliesCommandsAndEmitsEvents() async throws {
        let mock = MockBridgeClient(latency: .milliseconds(5))
        let stream = mock.events()
        #expect(await eventually { await mock.streamCount > 0 })
        try await mock.send(.power(false), toGroupedLight: "mock-group-0")
        var iterator = stream.makeAsyncIterator()
        let events = try #require(try await iterator.next())
        #expect(events.first?.data.contains { $0.type == "grouped_light" && $0.id == "mock-group-0" && $0.on?.on == false } == true)
        #expect(await mock.currentHome.room("mock-room-0")?.isOn == false)
    }
}
