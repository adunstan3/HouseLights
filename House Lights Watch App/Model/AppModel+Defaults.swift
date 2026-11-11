import Foundation

/// Room defaults and temporary colors (milestone 5).
extension AppModel {
    /// If Back to default was tapped while the room was off, turns it on in its default.
    /// Returns false when there's nothing pending, so a plain "on" is sent instead.
    func turnOnWithDefault(_ roomID: String) -> Bool { false }
}
