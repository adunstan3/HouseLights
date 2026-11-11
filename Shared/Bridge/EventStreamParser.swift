import Foundation

/// Parses server-sent events (text/event-stream) byte by byte. An event is a block of
/// `field: value` lines ended by a blank line; the Hue bridge sends `id:` and `data:`
/// (a JSON array) and occasional `: comment` keep-alives. We parse bytes ourselves
/// because `AsyncBytes.lines` drops the blank lines that end each event.
nonisolated struct EventStreamParser: Sendable {
    private var line: [UInt8] = []
    private var dataLines: [String] = []

    /// Feeds one byte; returns an event's data when a blank line completes it.
    mutating func feed(_ byte: UInt8) -> String? {
        if byte == UInt8(ascii: "\n") {
            let text = String(decoding: line, as: UTF8.self)
            line.removeAll(keepingCapacity: true)
            return process(text.hasSuffix("\r") ? String(text.dropLast()) : text)
        }
        line.append(byte)
        return nil
    }

    /// Feeds many bytes (for tests).
    mutating func feed(_ bytes: some Sequence<UInt8>) -> [String] {
        bytes.compactMap { feed($0) }
    }

    private mutating func process(_ text: String) -> String? {
        if text.isEmpty {
            guard !dataLines.isEmpty else { return nil }
            defer { dataLines.removeAll() }
            return dataLines.joined(separator: "\n")
        }
        if text.hasPrefix(":") { return nil }   // comment / keep-alive
        if text.hasPrefix("data:") {
            var value = text.dropFirst(5)
            if value.first == " " { value = value.dropFirst() }
            dataLines.append(String(value))
        }
        return nil   // id:, event:, retry: are not needed
    }

    static func decode(_ data: String) throws -> [HueEvent] {
        try JSONDecoder().decode([HueEvent].self, from: Data(data.utf8))
    }
}
