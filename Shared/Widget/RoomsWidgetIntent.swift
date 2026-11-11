import AppIntents

/// The widget's configuration: which 2–4 rooms it shows. Picked when adding the widget
/// and changed by editing it (watchOS 26 lets people configure widgets on the watch).
struct RoomsWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Rooms"
    static let description = IntentDescription("Choose up to four rooms to switch from the Smart Stack.")

    @Parameter(title: "Rooms", size: 4)
    var rooms: [RoomEntity]?

    init() {}
    init(rooms: [RoomEntity]) { self.rooms = rooms }
}
