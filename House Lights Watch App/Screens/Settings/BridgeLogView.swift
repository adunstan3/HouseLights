import SwiftUI

/// Settings › Bridge › Log: every request, response code and error, newest first.
/// This is the one screen meant to scroll — it's for the first test at home. The share
/// button (by the clock) sends the log as text. Below the log: Save bridge replies (the raw
/// resource lists, to share when something looks wrong), Remove House Lights scenes, and
/// Clear log.
struct BridgeLogView: View {
    @Environment(BridgeLog.self) private var log
    @Environment(AppModel.self) private var app
    @State private var savedReplies: URL?
    @State private var busy = false
    @State private var confirmRemove = false

    var body: some View {
        List {
            if log.entries.isEmpty {
                Text("Nothing logged yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(log.entries.reversed()) { entry in
                LogRow(entry: entry)
                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 6))
            }
            tools
        }
        .environment(\.defaultMinListRowHeight, 20)
        .navigationTitle("Log")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: app.logText, subject: Text("House Lights log")) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                }
                .tint(Theme.secondaryButton)
                .disabled(log.entries.isEmpty)
                .accessibilityLabel("Share log")
                .accessibilityIdentifier("shareLog")
            }
        }
        .confirmationDialog("Remove House Lights scenes?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove \(app.ownSceneCount) scenes", role: .destructive) {
                busy = true
                Task { await app.removeAllScenes(); busy = false }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deletes room defaults, hybrids and remote scenes. A dimmer set to a “House Lights Now” scene stops working until you set it again.")
        }
    }

    @ViewBuilder
    private var tools: some View {
        Section {
            if let savedReplies {
                ShareLink(item: savedReplies) { Label("Share bridge replies", systemImage: "square.and.arrow.up") }
                    .accessibilityIdentifier("shareReplies")
            } else {
                Button {
                    busy = true
                    Task { savedReplies = await app.saveBridgeReplies(); busy = false }
                } label: {
                    Label("Save bridge replies", systemImage: "square.and.arrow.down")
                }
                .accessibilityIdentifier("saveReplies")
            }
            if app.ownSceneCount > 0 {
                Button(role: .destructive) { confirmRemove = true } label: {
                    Label("Remove House Lights scenes", systemImage: "trash")
                }
                .accessibilityIdentifier("removeScenes")
            }
            if !log.entries.isEmpty {
                Button("Clear log", role: .destructive) { log.clear() }
            }
        }
        .disabled(busy)
    }
}

private struct LogRow: View {
    let entry: BridgeLog.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(entry.date.formatted(.dateTime.hour().minute().second())) · \(entry.kind.rawValue)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(color)
            Text(entry.text)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch entry.kind {
        case .error: .red
        case .request: Theme.accent
        case .response: .green
        case .info, .event: .secondary
        }
    }
}
