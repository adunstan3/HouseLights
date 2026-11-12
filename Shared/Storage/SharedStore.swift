import Foundation

/// Everything the watch keeps that the bridge doesn't, in App Group UserDefaults so the
/// widget and Siri intents see it too. See SPEC.md › Data stored on the watch.
nonisolated struct SharedStore: @unchecked Sendable {
    let defaults: UserDefaults

    init(defaults: UserDefaults = AppGroup.defaults) { self.defaults = defaults }

    private enum Key: String {
        case bridgeIP, gridOrder, temporaryRooms, pendingDefaults, zeroDimmed, lastKnownRooms, gridArrangement, remoteRooms
    }

    var bridgeIP: String? {
        get { defaults.string(forKey: Key.bridgeIP.rawValue) }
        nonmutating set { defaults.set(newValue, forKey: Key.bridgeIP.rawValue) }
    }

    /// Room and zone ids in the user's grid order.
    var gridOrder: [String] {
        get { defaults.stringArray(forKey: Key.gridOrder.rawValue) ?? [] }
        nonmutating set { defaults.set(newValue, forKey: Key.gridOrder.rawValue) }
    }

    /// Where each room sits on the grid (Arrange), as JSON; nil until arranged.
    var gridArrangement: GridArrangement? {
        get { decode(Key.gridArrangement) }
        nonmutating set { encode(newValue, Key.gridArrangement) }
    }

    /// Rooms whose "House Lights Now" remote scene the watch keeps up to date.
    var remoteRooms: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.remoteRooms.rawValue) ?? []) }
        nonmutating set { defaults.set(Array(newValue).sorted(), forKey: Key.remoteRooms.rawValue) }
    }

    /// Rooms showing a temporary color, with the color the app set.
    var temporaryRooms: [String: LightColor] {
        get { decode(Key.temporaryRooms) ?? [:] }
        nonmutating set { encode(newValue, Key.temporaryRooms) }
    }

    /// Rooms that should turn on in their default color next time (Back to default while off).
    var pendingDefaults: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.pendingDefaults.rawValue) ?? []) }
        nonmutating set { defaults.set(Array(newValue).sorted(), forKey: Key.pendingDefaults.rawValue) }
    }

    /// Rooms the Crown dimmed to 0% (and so turned off); a tap brings them back at 70%.
    var zeroDimmed: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.zeroDimmed.rawValue) ?? []) }
        nonmutating set { defaults.set(Array(newValue).sorted(), forKey: Key.zeroDimmed.rawValue) }
    }

    /// Last-known rooms, for the widget and a fast first paint.
    var lastKnownRooms: [Room] {
        get { decode(Key.lastKnownRooms) ?? [] }
        nonmutating set { encode(newValue, Key.lastKnownRooms) }
    }

    private func decode<T: Decodable>(_ key: Key) -> T? {
        defaults.data(forKey: key.rawValue).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private func encode<T: Encodable>(_ value: T, _ key: Key) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key.rawValue)
    }
}

nonisolated enum GridOrder {
    /// Rooms in the saved order; ids the order doesn't know go to the end in bridge order.
    static func apply(_ order: [String], to rooms: [Room]) -> [Room] {
        let byID = Dictionary(rooms.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let known = order.compactMap { byID[$0] }
        let knownIDs = Set(known.map(\.id))
        return known + rooms.filter { !knownIDs.contains($0.id) }
    }
}
