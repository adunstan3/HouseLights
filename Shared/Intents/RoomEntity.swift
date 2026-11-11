import AppIntents
import Foundation

/// A Hue room or zone for Siri and the widget, known by its Hue name.
nonisolated struct RoomEntity: AppEntity, Identifiable, Hashable, Sendable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Room"
    static let defaultQuery = RoomQuery()

    var id: String
    var name: String
    var iconName: String

    init(id: String, name: String, iconName: String) {
        self.id = id; self.name = name; self.iconName = iconName
    }

    init(_ room: Room) { self.init(id: room.id, name: room.name, iconName: room.iconName) }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: iconName))
    }
}

/// Rooms come from the last-known list the app keeps in the App Group, refreshed from the
/// bridge when that list is empty.
nonisolated struct RoomQuery: EntityStringQuery {
    func entities(for identifiers: [RoomEntity.ID]) async throws -> [RoomEntity] {
        let rooms = await Self.rooms()
        return identifiers.compactMap { id in rooms.first { $0.id == id } }
    }

    func entities(matching string: String) async throws -> [RoomEntity] {
        let needle = string.lowercased().replacingOccurrences(of: "the ", with: "")
        return await Self.rooms().filter { $0.name.lowercased().contains(needle) || needle.contains($0.name.lowercased()) }
    }

    func suggestedEntities() async throws -> [RoomEntity] { await Self.rooms() }

    static func rooms() async -> [RoomEntity] {
        var rooms = SharedStore().lastKnownRooms
        if rooms.isEmpty, let home = try? await RoomActions.fetchHome() { rooms = home.rooms }
        let order = SharedStore().gridOrder
        return GridOrder.apply(order, to: rooms).map(RoomEntity.init)
    }
}
