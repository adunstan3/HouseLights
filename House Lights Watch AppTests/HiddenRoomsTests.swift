import Foundation
import Testing
@testable import House_Lights_Watch_App

/// Arrange › Hidden rooms: hidden rooms leave the grid, the Crown and All off, and come back
/// in the first free spot.
@MainActor
struct HiddenRoomsTests {
    func ready() async -> (AppModel, MockBridgeClient) {
        let (app, mock) = ConnectionTests.makeApp(paired: true)
        await app.start()
        return (app, mock)
    }

    @Test func hidingTakesARoomOffTheGridAndLeavesTheOthersInPlace() async {
        let (app, _) = await ready()
        let before = app.arrangement
        let kitchen = "mock-room-1"
        app.hideRoom(kitchen, from: before)
        #expect(!app.rooms.contains { $0.id == kitchen })
        #expect(app.hiddenRoomList.map(\.id) == [kitchen])
        #expect(app.store.hiddenRooms == [kitchen])
        for (id, slot) in before.slots where id != kitchen { #expect(app.arrangement.slots[id] == slot) }
        #expect(app.allRooms.count == 6)   // Remote scenes still lists it
    }

    @Test func showingPutsItBackInTheFirstFreeSpot() async {
        let (app, _) = await ready()
        let before = app.arrangement
        let living = "mock-room-0"                     // top left
        app.hideRoom(living, from: before)
        app.showRoom(living)
        #expect(app.hiddenRooms.isEmpty)
        #expect(app.arrangement.slots[living] == before.firstFreeAfterRemoving(living))
        #expect(app.savedArrangement?.slots[living] != nil)   // saved there
    }

    @Test func crownAndAllOffLeaveHiddenRoomsAlone() async {
        let (app, mock) = await ready()
        let kitchen = "mock-room-1"                     // on, 100%
        app.hideRoom(kitchen, from: app.arrangement)
        app.crownStep(-2)
        #expect(app.room(kitchen)?.brightness == 100)
        app.allOff()
        #expect(app.room(kitchen)?.isOn == true)
        #expect(app.room("mock-room-0")?.isOn == false)
        #expect(await eventually { await mock.currentHome.room("mock-room-0")?.isOn == false })
        #expect(await mock.currentHome.room(kitchen)?.isOn == true)
    }

    @Test func hiddenRoomsAreKeptAcrossLaunches() async {
        let (app, _) = await ready()
        app.hideRoom("mock-room-2", from: app.arrangement)
        let again = AppModel(environment: app.environment, store: app.store, log: BridgeLog(fileURL: nil))
        await again.start()
        #expect(!again.rooms.contains { $0.id == "mock-room-2" })
        #expect(again.hiddenRoomList.map(\.id) == ["mock-room-2"])
    }
}

extension GridArrangement {
    /// Where `id` would go back to: the first free full-column spot once it's gone.
    func firstFreeAfterRemoving(_ id: String) -> Slot {
        var copy = self
        copy.slots[id] = nil
        return copy.firstFree(rows: GridArrangement.baseRows(for: copy.slots.count + 1))
    }
}
