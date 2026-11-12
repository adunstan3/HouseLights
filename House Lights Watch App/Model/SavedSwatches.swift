import Foundation

/// A color pinned on the Color wheel screen, saved as a wheel position (hue and saturation)
/// so it fits any room: it's converted to that room's xy gamut when applied.
nonisolated struct SavedSwatch: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var hue: Double
    var saturation: Double

    /// Close enough to count as the same color (the wheel can't be hit more exactly by finger).
    func matches(hue h: Double, saturation s: Double) -> Bool {
        let dh = abs(hue - h)
        return min(dh, 1 - dh) < 0.015 && abs(saturation - s) < 0.04
    }

    var rgb: RGB { ColorMath.rgb(hue: hue, saturation: saturation) }
}

nonisolated enum SwatchList {
    /// Adds a color at the front unless an almost identical one is already saved.
    /// Returns the new list and whether it changed.
    static func adding(_ hue: Double, _ saturation: Double, to list: [SavedSwatch]) -> ([SavedSwatch], Bool) {
        if list.contains(where: { $0.matches(hue: hue, saturation: saturation) }) { return (list, false) }
        return ([SavedSwatch(hue: hue, saturation: saturation)] + list, true)
    }
}

extension SharedStore {
    nonisolated private static let swatchesKey = "savedSwatches"

    /// Pinned colors, shared by every room.
    nonisolated var savedSwatches: [SavedSwatch] {
        get {
            defaults.data(forKey: Self.swatchesKey).flatMap { try? JSONDecoder().decode([SavedSwatch].self, from: $0) } ?? []
        }
        nonmutating set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Self.swatchesKey) }
    }
}

extension AppModel {
    /// Pins a color; returns false if it was already saved.
    @discardableResult
    func pinSwatch(hue: Double, saturation: Double) -> Bool {
        let (list, added) = SwatchList.adding(hue, saturation, to: savedSwatches)
        if added { savedSwatches = list }
        return added
    }

    func removeSwatch(_ id: SavedSwatch.ID) {
        savedSwatches.removeAll { $0.id == id }
    }
}
