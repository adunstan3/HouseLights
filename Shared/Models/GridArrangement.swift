import Foundation

/// A place on the grid: a row, and a column in half-tile steps. With three across, `half`
/// runs 0…4: 0, 2 and 4 are the usual columns; 1 and 3 sit half-way between them.
nonisolated struct Slot: Codable, Hashable, Sendable {
    var row: Int
    var half: Int

    /// Distance between slot centres, in tiles.
    func distance(to other: Slot) -> Double {
        hypot(Double(half - other.half) / 2, Double(row - other.row))
    }
}

/// Where each room sits on the grid. Rooms can be anywhere (gaps are kept, nothing packs
/// towards the top left), including half-way between columns. Two rooms in a row must be
/// at least a tile apart.
nonisolated struct GridArrangement: Codable, Equatable, Sendable {
    var columns: Int
    var slots: [String: Slot]

    var maxHalf: Int { 2 * (columns - 1) }
    var rowsUsed: Int { (slots.values.map(\.row).max() ?? -1) + 1 }

    /// Rooms from top-left to bottom-right (for the widget, Siri and VoiceOver).
    var readingOrder: [String] {
        slots.sorted { a, b in
            (a.value.row, a.value.half, a.key) < (b.value.row, b.value.half, b.key)
        }.map(\.key)
    }

    static func overlap(_ a: Slot, _ b: Slot) -> Bool { a.row == b.row && abs(a.half - b.half) < 2 }

    func isFree(_ slot: Slot, ignoring: Set<String> = []) -> Bool {
        guard slot.row >= 0, slot.half >= 0, slot.half <= maxHalf else { return false }
        return !slots.contains { !ignoring.contains($0.key) && Self.overlap($0.value, slot) }
    }

    /// Columns for this many rooms: two across for 1–4, three for more. Never four.
    static func columns(for count: Int) -> Int { count <= 4 ? 2 : 3 }

    /// Rows that fit the screen: 2 (two across) or 3, more if there are too many rooms.
    static func baseRows(for count: Int) -> Int {
        let c = columns(for: count)
        return c == 2 ? 2 : max(3, Int((Double(count) / 3).rounded(.up)))
    }

    /// The arrangement for these rooms. Saved spots are kept where they're still valid;
    /// rooms without one (new rooms, or after switching between two and three across) go to
    /// the first free spot in reading order, following `roomIDs`' order.
    static func make(roomIDs: [String], saved: GridArrangement?) -> GridArrangement {
        let columns = columns(for: roomIDs.count)
        var result = GridArrangement(columns: columns, slots: [:])
        var unplaced: [String] = []
        let keep = saved?.columns == columns ? saved : nil
        for id in roomIDs {
            if let slot = keep?.slots[id], result.isFree(slot) { result.slots[id] = slot }
            else { unplaced.append(id) }
        }
        for id in unplaced {
            result.slots[id] = result.firstFree(rows: baseRows(for: roomIDs.count))
        }
        return result
    }

    /// The first free full-column spot, row by row (adding a row if all are taken).
    func firstFree(rows: Int) -> Slot {
        for row in 0..<max(rows, rowsUsed) + 1 {
            for half in stride(from: 0, through: maxHalf, by: 2) where isFree(Slot(row: row, half: half)) {
                return Slot(row: row, half: half)
            }
        }
        return Slot(row: max(rows, rowsUsed), half: 0)
    }

    /// Puts `id` at `target`. Rooms it lands on move to the nearest free spot (within the
    /// rows on screen; a new row only if nothing is free).
    func placing(_ id: String, at target: Slot, rows: Int) -> GridArrangement {
        var result = self
        result.slots[id] = target
        let displaced = slots.filter { $0.key != id && Self.overlap($0.value, target) }
            .sorted { ($0.value.distance(to: target), $0.key) < ($1.value.distance(to: target), $1.key) }
        for (other, from) in displaced {
            result.slots[other] = nil
            result.slots[other] = result.nearestFree(to: from, rows: rows)
        }
        return result
    }

    /// The free spot closest to `slot`; ties go to the upper, left-most full column.
    func nearestFree(to slot: Slot, rows: Int) -> Slot {
        func search(_ rowCount: Int) -> Slot? {
            var best: (Slot, Double)?
            for row in 0..<rowCount {
                for half in 0...maxHalf {
                    let s = Slot(row: row, half: half)
                    guard isFree(s) else { continue }
                    let d = s.distance(to: slot) + (half % 2 == 1 ? 0.001 : 0)   // prefer full columns
                    if best == nil || d < best!.1 - 1e-9 { best = (s, d) }
                }
            }
            return best?.0
        }
        let rowCount = max(rows, rowsUsed)
        return search(rowCount) ?? search(rowCount + 1) ?? Slot(row: rowCount, half: 0)
    }
}
