import Foundation
import Observation

/// Every request, response code and error, for Settings › Bridge › Log. Kept in the App
/// Group folder so it survives relaunches (and the widget's requests show up too).
@MainActor @Observable
final class BridgeLog {
    nonisolated enum Kind: String, Codable, Sendable { case request, response, error, info, event }

    nonisolated struct Entry: Codable, Sendable, Identifiable, Hashable {
        var id = UUID()
        var date: Date
        var kind: Kind
        var text: String
    }

    private(set) var entries: [Entry] = []
    let maxEntries: Int
    private let fileURL: URL?
    private var saveTask: Task<Void, Never>?

    /// `fileURL: nil` keeps the log in memory only (tests, previews).
    init(fileURL: URL? = BridgeLog.defaultURL, maxEntries: Int = 500) {
        self.fileURL = fileURL
        self.maxEntries = maxEntries
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = Array(saved.suffix(maxEntries))
        }
    }

    nonisolated static var defaultURL: URL { AppGroup.containerURL.appending(path: "bridge-log.json") }

    func add(_ kind: Kind, _ text: String, date: Date = .now) {
        entries.append(Entry(date: date, kind: kind, text: text))
        if entries.count > maxEntries { entries.removeFirst(entries.count - maxEntries) }
        scheduleSave()
    }

    func clear() {
        entries.removeAll()
        scheduleSave()
    }

    /// A logger the (nonisolated) bridge client can call from any thread.
    nonisolated var sink: LogSink {
        LogSink { kind, text in
            let date = Date()
            Task { @MainActor in self.add(kind, text, date: date) }
        }
    }

    func saveNow() {
        saveTask?.cancel()
        guard let fileURL else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(entries).write(to: fileURL, options: .atomic)
    }

    private func scheduleSave() {
        guard fileURL != nil else { return }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            saveNow()
        }
    }
}

/// A thread-safe logging closure handed to the bridge client.
nonisolated struct LogSink: Sendable {
    let write: @Sendable (BridgeLog.Kind, String) -> Void
    init(_ write: @escaping @Sendable (BridgeLog.Kind, String) -> Void) { self.write = write }
    func callAsFunction(_ kind: BridgeLog.Kind, _ text: String) { write(kind, text) }
    static let none = LogSink { _, _ in }
}
