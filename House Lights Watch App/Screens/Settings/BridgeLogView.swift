import SwiftUI

/// Settings › Bridge › Log: every request, response code and error, newest first.
/// This is the one screen meant to scroll — it's for the first test at home.
struct BridgeLogView: View {
    @Environment(BridgeLog.self) private var log

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
            if !log.entries.isEmpty {
                Button("Clear log", role: .destructive) { log.clear() }
            }
        }
        .environment(\.defaultMinListRowHeight, 20)
        .navigationTitle("Log")
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
