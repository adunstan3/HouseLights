import SwiftUI

/// Milestone 1 stand-in: shows what the bridge layer loaded, with a link to the log.
/// Milestone 2 replaces this with first-launch routing; milestone 3 adds the grid.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(status)
                        .font(.footnote)
                }
                ForEach(model.rooms) { room in
                    HStack {
                        Image(systemName: room.iconName)
                        Text(room.name)
                        Spacer()
                        Text(room.isOn ? "\(room.percent)%" : "Off")
                            .foregroundStyle(.secondary)
                    }
                    .font(.footnote)
                }
                NavigationLink("Bridge log") { BridgeLogView() }
            }
            .navigationTitle("House Lights")
        }
    }

    private var status: String {
        switch model.phase {
        case .starting, .loading: "Loading…"
        case .unpaired: "Not paired"
        case .ready: model.streamConnected ? "Live" : "Loaded"
        case .unreachable(let why): why
        }
    }
}
