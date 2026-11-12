import Foundation

/// Warmth and color. Whichever was touched last is what the lights show.
extension AppModel {
    /// Warmth slider. The kelvin is clamped to what every bulb in the room supports.
    func setWarmth(kelvin: Int, roomID: String) {
        guard let room = room(roomID) else { return }
        var mirek = ColorMath.mirek(fromKelvin: kelvin)
        if let r = room.mirekRange { mirek = min(max(mirek, r.lowerBound), r.upperBound) }
        apply(.temperature(mirek: mirek), command: GroupedLightCommand(mirek: mirek), to: room)
    }

    /// Color wheel (sent when the finger lifts, or a saved swatch is tapped). `xy` is already
    /// fitted to the room's gamut.
    func setColor(_ xy: XY, roomID: String) {
        guard let room = room(roomID) else { return }
        apply(.xy(xy), command: GroupedLightCommand(xy: xy), to: room)
    }

    private func apply(_ color: LightColor, command: GroupedLightCommand, to room: Room) {
        // An off room stays off: the color is sent without "on". Current Hue bulbs keep a
        // change made while off and show it when next switched on.
        clearHybrid(room.id)
        let wasDefault = prepareColorChange(room)
        update(room.id) { $0.color = color }
        for id in room.lightIDs where home.lights[id] != nil {
            home.lights[id]?.color = color
        }
        enqueue(command, for: room)
        noteColorChange(room.id, color: color, wasDefault: wasDefault)
        remoteSceneChanged(room.id)
    }
}
