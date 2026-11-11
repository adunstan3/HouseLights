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

    /// Color wheel (sent when the finger lifts). `xy` is already fitted to the room's gamut.
    func setColor(_ xy: XY, roomID: String) {
        guard let room = room(roomID) else { return }
        apply(.xy(xy), command: GroupedLightCommand(xy: xy), to: room)
    }

    private func apply(_ color: LightColor, command: GroupedLightCommand, to room: Room) {
        var command = command
        if !room.isOn { command.on = true }   // changing the color of an off room turns it on
        let wasDefault = prepareColorChange(room)
        update(room.id) { $0.color = color; $0.isOn = true }
        for id in room.lightIDs where home.lights[id] != nil {
            home.lights[id]?.color = color
            home.lights[id]?.isOn = true
        }
        enqueue(command, for: room)
        noteColorChange(room.id, color: color, wasDefault: wasDefault)
    }
}
