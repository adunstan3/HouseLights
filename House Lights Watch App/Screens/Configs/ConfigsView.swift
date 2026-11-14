import SwiftUI
import WatchKit

/// Grid › bookmark: saved whole-house configurations. Save current lights (asks for a name)
/// sits at the top; the saved ones are listed under it, newest first. Tap one to load it and
/// go back to the grid. Each has a pencil (rename) and a save-over button (replace its lights
/// with the current ones, after a confirmation). Swipe left to delete. Back is top left.
struct ConfigsView: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @State private var overwriting: HouseConfig?

    var body: some View {
        List {
            Section {
                TextFieldLink(prompt: Text("Name")) {
                    Label("Save current lights", systemImage: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                } onSubmit: { name in
                    if app.saveConfig(named: name) != nil { WKInterfaceDevice.current().play(.success) }
                }
                .accessibilityIdentifier("saveCurrent")
            }
            Section {
                if app.houseConfigs.isEmpty {
                    Text("Nothing saved yet. Set the lights the way you like, then save them here.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                ForEach(app.houseConfigs) { config in
                    row(config)
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 6))
                }
                .onDelete { offsets in
                    for i in offsets { app.deleteConfig(app.houseConfigs[i].id) }
                }
            }
        }
        .navigationTitle("Saved lights")
        .confirmationDialog("Save the current lights over this?", isPresented: Binding(
            get: { overwriting != nil }, set: { if !$0 { overwriting = nil } }),
                            titleVisibility: .visible, presenting: overwriting) { config in
            Button("Save over “\(config.name)”", role: .destructive) {
                app.overwriteConfig(config.id)
                WKInterfaceDevice.current().play(.success)
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func row(_ config: HouseConfig) -> some View {
        HStack(spacing: 6) {
            Button {
                app.loadConfig(config.id)
                WKInterfaceDevice.current().play(.click)
                router.popToRoot()
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(config.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Text(summary(config))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Load \(config.name)")
            .accessibilityIdentifier("config-\(config.name)")

            TextFieldLink(prompt: Text("Name")) {
                icon("pencil")
            } onSubmit: { name in
                app.renameConfig(config.id, to: name)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Rename \(config.name)")
            .accessibilityIdentifier("rename-\(config.name)")

            Button { overwriting = config } label: { icon("square.and.arrow.down") }
                .buttonStyle(.plain)
                .accessibilityLabel("Save current lights over \(config.name)")
                .accessibilityIdentifier("overwrite-\(config.name)")
        }
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(Theme.secondaryButton, in: Circle())
    }

    /// "3 of 6 rooms on".
    private func summary(_ config: HouseConfig) -> String {
        let on = config.rooms.filter(\.isOn).count
        return on == 0 ? "All off" : "\(on) of \(config.rooms.count) rooms on"
    }
}
