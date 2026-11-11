import Foundation

/// Room defaults and temporary colors (milestone 5).
extension AppModel {
    /// If Back to default was tapped while the room was off, turns it on in its default.
    /// Returns false when there's nothing pending, so a plain "on" is sent instead.
    func turnOnWithDefault(_ roomID: String) -> Bool { false }

    /// Called before a warmth or color change. Returns whether the room was showing its default.
    func prepareColorChange(_ room: Room) -> Bool { true }

    /// Called after a warmth or color change.
    func noteColorChange(_ roomID: String, color: LightColor, wasDefault: Bool) {}
}
