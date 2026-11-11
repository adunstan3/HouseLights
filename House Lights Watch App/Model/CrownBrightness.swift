import Foundation

/// The Digital Crown on the grid (SPEC.md › Behavior details): each step adds the same
/// 5 points to every room that's on, so their differences are kept. Rooms stop at 100%;
/// a room that reaches 0% turns off. Rooms that are off, and zones, are untouched.
nonisolated enum CrownBrightness {
    static let step: Double = 5
    /// A room dimmed to 0% comes back at this brightness when tapped.
    static let backOnLevel: Double = 70

    enum Change: Equatable, Sendable {
        case brightness(Double)
        case off
    }

    static func apply(steps: Int, to rooms: [Room]) -> [String: Change] {
        guard steps != 0 else { return [:] }
        var out: [String: Change] = [:]
        for room in rooms where room.kind == .room && room.isOn {
            let target = room.brightness.rounded() + Double(steps) * step
            if target <= 0 { out[room.id] = .off }
            else { out[room.id] = .brightness(min(target, 100)) }
        }
        return out
    }

    /// Rooms the Crown can change right now (for the "Brighter · 4 on" pill).
    static func affected(_ rooms: [Room]) -> Int { rooms.filter { $0.kind == .room && $0.isOn }.count }
}
