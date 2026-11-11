import Foundation
import SwiftUI
import Testing
import UIKit
@testable import House_Lights_Watch_App

struct TurnOnPlanTests {
    let room = Room(id: "r", kind: .room, name: "R", archetype: "other", groupedLightID: "g", lightIDs: [], isOn: false, brightness: 40)

    @Test func plainOnKeepsTheBulbsAsTheyWere() {
        #expect(TurnOnPlan.make(room: room, pendingDefault: false, zeroDimmed: false, defaultSceneID: "s") == .on)
    }

    @Test func dimmedToZeroComesBackAtSeventy() {
        #expect(TurnOnPlan.make(room: room, pendingDefault: false, zeroDimmed: true, defaultSceneID: nil) == .onAt(70))
    }

    @Test func pendingDefaultRecallsTheScene() {
        #expect(TurnOnPlan.make(room: room, pendingDefault: true, zeroDimmed: false, defaultSceneID: "s") == .recallDefault(sceneID: "s", brightness: 40))
        #expect(TurnOnPlan.make(room: room, pendingDefault: true, zeroDimmed: false, defaultSceneID: nil) == .on)
    }
}

@MainActor
struct IntentTests {
    @Test func siriActionsChangeTheLastKnownRooms() async throws {
        let off = try await RoomActions.perform(.off, roomID: "mock-room-0")
        #expect(!off.isOn)
        #expect(SharedStore().lastKnownRooms.first { $0.id == "mock-room-0" }?.isOn == false)
        let dim = try await RoomActions.perform(.brightness(30), roomID: "mock-room-0")
        #expect(dim.isOn && dim.percent == 30)
        let warm = try await RoomActions.perform(.warmth(2000), roomID: "mock-room-0")
        #expect(warm.color == .temperature(mirek: 454))   // clamped to the room's range
    }

    @Test func toggleFlipsTheBridgesState() async throws {
        let bedroom = try await RoomActions.perform(.toggle, roomID: "mock-room-2")   // sample bedroom is off
        #expect(bedroom.isOn)
    }

    @Test func unknownRoomSaysSoPlainly() async {
        await #expect(throws: IntentError.roomGone) { try await RoomActions.perform(.on, roomID: "nope") }
        #expect(String(localized: IntentError.unreachable.localizedStringResource).contains("home Wi-Fi"))
    }

    @Test func widgetShowsConfiguredRoomsOrTheFirstThree() throws {
        let store = SharedStore(defaults: try #require(UserDefaults(suiteName: "test-\(UUID())")))
        store.lastKnownRooms = MockHome.sample().rooms
        #expect(WidgetRooms.resolve(configured: nil, store: store).map(\.name) == ["Living room", "Kitchen", "Bedroom"])
        #expect(WidgetRooms.resolve(configured: ["mock-room-4", "mock-room-0"], store: store).map(\.name) == ["Front door", "Living room"])
        #expect(WidgetRooms.resolve(configured: ["gone"], store: store).isEmpty)
    }

    @Test func roomQueryMatchesSpokenNames() async throws {
        SharedStore().lastKnownRooms = MockHome.sample().rooms
        let matches = try await RoomQuery().entities(matching: "the bedroom")
        #expect(matches.map(\.name) == ["Bedroom"])
    }

    /// Renders the widget and the Siri snippet to PNGs when SNAPSHOT_DIR is set
    /// (TEST_RUNNER_SNAPSHOT_DIR=… scripts/test.sh), to check them against the mockups.
    @Test func renderWidgetAndSnippet() throws {
        guard let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] else { return }
        let rooms = MockHome.sample().rooms
        func save(_ view: some View, _ name: String, _ size: CGSize) throws {
            let r = ImageRenderer(content: view.frame(width: size.width, height: size.height).background(Color.black))
            r.scale = 2
            let data = try #require(r.uiImage?.pngData())
            try data.write(to: URL(fileURLWithPath: dir).appending(path: "\(name).png"))
        }
        let widget = RoomsWidgetView(rooms: [rooms[0], rooms[2], rooms[1]])
            .padding(8).background(RoundedRectangle(cornerRadius: 18).fill(Theme.card))
        try save(widget, "widget3", CGSize(width: 188, height: 90))
        try save(RoomsWidgetView(rooms: Array(rooms.prefix(4))).padding(8).background(RoundedRectangle(cornerRadius: 18).fill(Theme.card)), "widget4", CGSize(width: 188, height: 90))
        var bedroom = rooms[2]; bedroom.isOn = false
        var living = rooms[0]; living.brightness = 30
        try save(VStack(spacing: 10) {
            RoomSnippetView(room: bedroom, action: .off)
            RoomSnippetView(room: living, action: .brightness)
        }, "snippets", CGSize(width: 190, height: 140))
    }
}
