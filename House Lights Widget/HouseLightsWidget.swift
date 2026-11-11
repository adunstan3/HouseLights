import AppIntents
import SwiftUI
import WidgetKit

@main
struct HouseLightsWidgets: WidgetBundle {
    var body: some Widget { RoomsWidget() }
}

struct RoomsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "RoomsWidget", intent: RoomsWidgetIntent.self, provider: RoomsProvider()) { entry in
            RoomsWidgetView(rooms: entry.rooms)
                .containerBackground(for: .widget) { Theme.card }
        }
        .configurationDisplayName("House Lights")
        .description("Switch up to four rooms from the Smart Stack.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct RoomsEntry: TimelineEntry {
    var date: Date
    var rooms: [Room]
}

/// Shows the last-known state from the App Group. A toggle re-checks the bridge (in
/// ToggleRoomIntent) and WidgetKit reloads the timeline after it; there's no polling.
struct RoomsProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> RoomsEntry {
        RoomsEntry(date: .now, rooms: Array(MockHome.sample().rooms.prefix(3)))
    }

    func snapshot(for configuration: RoomsWidgetIntent, in context: Context) async -> RoomsEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: RoomsWidgetIntent, in context: Context) async -> Timeline<RoomsEntry> {
        Timeline(entries: [entry(for: configuration)], policy: .never)
    }

    /// No presets: on watchOS 26 an empty list lets people choose the rooms themselves.
    func recommendations() -> [AppIntentRecommendation<RoomsWidgetIntent>] { [] }

    private func entry(for configuration: RoomsWidgetIntent) -> RoomsEntry {
        RoomsEntry(date: .now, rooms: WidgetRooms.resolve(configured: configuration.rooms?.map(\.id)))
    }
}
