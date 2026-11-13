import Foundation

/// On/off and brightness. Every change updates the UI at once and goes to the bridge
/// through the sender (at most once a second per room, latest value only).
extension AppModel {
    func room(_ id: String) -> Room? { home.room(id) }

    /// Tap on a tile, or the Room screen's power button.
    func toggle(_ roomID: String) {
        guard let room = room(roomID) else { return }
        setPower(!room.isOn, roomID: roomID)
    }

    func setPower(_ on: Bool, roomID: String) {
        guard let room = room(roomID) else { return }
        if !on {
            update(roomID) { $0.isOn = false }
            enqueue(.power(false), for: room)
            return
        }
        if turnOnWithDefault(roomID) { return }   // Back to default while off (milestone 5)
        if turnOnWithMix(roomID) { return }       // a hybrid chosen while off
        if store.zeroDimmed.contains(roomID) {
            // Only a room the Crown or slider dimmed to 0% comes back at 70% (the bulbs would
            // otherwise return at the very bottom). A room switched off with a tap comes back
            // at its own last brightness.
            store.zeroDimmed.remove(roomID)
            update(roomID) { $0.isOn = true; $0.brightness = CrownBrightness.backOnLevel }
            enqueue(GroupedLightCommand(on: true, brightness: CrownBrightness.backOnLevel), for: room)
        } else {
            update(roomID) { $0.isOn = true }
            enqueue(.power(true), for: room)
        }
    }

    /// Room screen brightness (Crown). 0 turns the room off, like the grid.
    func setBrightness(_ value: Double, roomID: String) {
        guard let room = room(roomID) else { return }
        let v = min(max(value.rounded(), 0), 100)
        if v <= 0 {
            store.zeroDimmed.insert(roomID)
            update(roomID) { $0.isOn = false; $0.brightness = 0 }
            enqueue(.power(false), for: room)
            remoteSceneChanged(roomID)   // the remote brings it back at 70%
        } else {
            store.zeroDimmed.remove(roomID)
            update(roomID) { $0.isOn = true; $0.brightness = v }
            enqueue(GroupedLightCommand(on: room.isOn ? nil : true, brightness: v), for: room)
            remoteSceneChanged(roomID)
        }
    }

    /// One or more Crown steps on the grid.
    func crownStep(_ steps: Int) {
        let changes = CrownBrightness.apply(steps: steps, to: home.rooms)
        for (id, change) in changes {
            guard let room = room(id) else { continue }
            switch change {
            case .brightness(let b):
                update(id) { $0.brightness = b }
                enqueue(GroupedLightCommand(brightness: b), for: room)
                remoteSceneChanged(id)
            case .off:
                store.zeroDimmed.insert(id)
                update(id) { $0.isOn = false; $0.brightness = 0 }
                enqueue(.power(false), for: room)
                remoteSceneChanged(id)   // the remote brings it back at 70%
            }
        }
    }

    /// The grid's all-off button: one command to the bridge's all-lights group.
    func allOff() {
        for i in home.rooms.indices { home.rooms[i].isOn = false }
        if let all = home.allLightsGroupID {
            sender.enqueue(.power(false), to: all)
        } else {
            for room in home.rooms where room.kind == .room { sender.enqueue(.power(false), to: room.groupedLightID) }
        }
        let now = Date()
        for room in home.rooms { lastLocalChange[room.id] = now }
        store.lastKnownRooms = home.rooms
    }

    /// Arrange: where each room sits. The reading order is kept too (widget, Siri).
    func saveArrangement(_ arrangement: GridArrangement) {
        savedArrangement = arrangement
        gridOrder = arrangement.readingOrder
        log.add(.info, "Saved grid arrangement")
    }

    /// A plain order (VoiceOver moves, tests): rooms fill the grid in this order, no gaps.
    func saveOrder(_ ids: [String]) {
        savedArrangement = nil
        gridOrder = ids
        log.add(.info, "Saved grid order")
    }

    // MARK: Helpers

    func update(_ roomID: String, _ change: (inout Room) -> Void) {
        guard let i = home.rooms.firstIndex(where: { $0.id == roomID }) else { return }
        change(&home.rooms[i])
        store.lastKnownRooms = home.rooms
        scheduleWidgetRefresh()
    }

    func enqueue(_ command: GroupedLightCommand, for room: Room) {
        lastLocalChange[room.id] = Date()
        sender.enqueue(command, to: room.groupedLightID)
    }
}
