import Foundation

/// The one place Siri and the widget change lights. Each call reads the bridge, sends one
/// command, and updates the last-known rooms the app and widget show. Uses the same rules
/// as the app (TurnOnPlan, the Crown's 0% → 70%, temporary colors).
nonisolated enum RoomAction: Sendable, Equatable {
    case on, off, toggle
    case brightness(Int)
    case warmth(Int)
}

nonisolated enum RoomActions {
    /// Performs the action and returns the room's new state.
    @MainActor
    static func perform(_ action: RoomAction, roomID: String) async throws -> Room {
        let log = BridgeLog()
        defer { log.saveNow() }
        log.add(.info, "Intent: \(action) for \(roomID)")
        let store = SharedStore()
        let client = try makeClient(log: log.sink)
        let home: HomeSnapshot
        do { home = try await client.fetchHome() } catch { throw IntentError.from(error) }
        guard var room = home.room(roomID) else { throw IntentError.roomGone }

        var resolved = action
        if action == .toggle { resolved = room.isOn ? .off : .on }

        do {
            switch resolved {
            case .off, .brightness(0):
                try await client.send(.power(false), toGroupedLight: room.groupedLightID)
                if case .brightness = resolved { store.zeroDimmed.insert(roomID) }
                room.isOn = false
            case .on:
                let plan = TurnOnPlan.make(room: room, pendingDefault: store.pendingDefaults.contains(roomID),
                                           zeroDimmed: store.zeroDimmed.contains(roomID),
                                           defaultSceneID: home.defaults[roomID]?.id)
                switch plan {
                case .recallDefault(let id, let b):
                    try await client.recallScene(id: id, brightness: b)
                    store.pendingDefaults.remove(roomID)
                    room.color = home.defaults[roomID]?.color ?? room.color
                    room.brightness = b
                case .onAt(let b):
                    try await client.send(GroupedLightCommand(on: true, brightness: b), toGroupedLight: room.groupedLightID)
                    room.brightness = b
                case .on:
                    try await client.send(.power(true), toGroupedLight: room.groupedLightID)
                }
                store.zeroDimmed.remove(roomID)
                room.isOn = true
            case .brightness(let p):
                let b = Double(min(max(p, 1), 100))
                try await client.send(GroupedLightCommand(on: true, brightness: b), toGroupedLight: room.groupedLightID)
                store.zeroDimmed.remove(roomID)
                room.isOn = true
                room.brightness = b
            case .warmth(let k):
                var mirek = ColorMath.mirek(fromKelvin: min(max(k, ColorMath.minKelvin), ColorMath.maxKelvin))
                if let r = room.mirekRange { mirek = min(max(mirek, r.lowerBound), r.upperBound) }
                try await client.send(GroupedLightCommand(on: true, mirek: mirek), toGroupedLight: room.groupedLightID)
                let color = LightColor.temperature(mirek: mirek)
                if let d = home.defaults[roomID]?.color, d.isClose(to: color) { store.temporaryRooms[roomID] = nil }
                else if home.defaults[roomID] != nil { store.temporaryRooms[roomID] = color }
                store.pendingDefaults.remove(roomID)
                room.isOn = true
                room.color = color
            case .toggle:
                break
            }
        } catch {
            throw IntentError.from(error)
        }

        var rooms = home.rooms
        if let i = rooms.firstIndex(where: { $0.id == roomID }) { rooms[i] = room }
        store.lastKnownRooms = rooms
        return room
    }

    /// Reads the bridge (used when the last-known room list is empty).
    @MainActor
    static func fetchHome() async throws -> HomeSnapshot {
        let log = BridgeLog()
        defer { log.saveNow() }
        let home = try await makeClient(log: log.sink).fetchHome()
        SharedStore().lastKnownRooms = home.rooms
        return home
    }

    static func makeClient(log: LogSink) throws -> any BridgeClient {
        #if targetEnvironment(simulator)
        // The simulator can't reach the bridge: act on the sample home.
        return MockBridgeClient(home: MockHome.sample(), latency: .milliseconds(50), log: log)
        #else
        guard let credentials = BridgeCredentials.load() else { throw IntentError.notPaired }
        return HueBridgeClient(credentials: credentials, log: log)
        #endif
    }
}
