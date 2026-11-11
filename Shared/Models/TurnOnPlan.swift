import Foundation

/// How to turn a room on, shared by the app, the widget and Siri:
/// - Back to default was tapped while it was off → recall its default scene;
/// - the Crown dimmed it to 0% → on at 70%;
/// - otherwise a plain "on" (the bulbs come back as they were, temporary color included).
nonisolated enum TurnOnPlan: Equatable, Sendable {
    case recallDefault(sceneID: String, brightness: Double)
    case onAt(Double)
    case on

    static func make(room: Room, pendingDefault: Bool, zeroDimmed: Bool, defaultSceneID: String?) -> TurnOnPlan {
        if pendingDefault, let id = defaultSceneID, !id.isEmpty {
            return .recallDefault(sceneID: id, brightness: room.brightness >= 1 ? room.brightness : CrownBrightness.backOnLevel)
        }
        if zeroDimmed || room.brightness < 1 { return .onAt(CrownBrightness.backOnLevel) }
        return .on
    }
}
