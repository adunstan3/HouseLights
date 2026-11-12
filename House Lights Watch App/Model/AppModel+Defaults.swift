import Foundation

/// Room defaults and temporary colors (SPEC.md › Temporary colors and defaults).
///
/// Each room's default lives on the bridge as a scene "House Lights – <room>", created
/// from the room's current state the first time its warmth or color is changed. Any color
/// that differs from the default is *temporary* until Back to default or Set as default,
/// and survives off/on because Hue bulbs keep their color when switched.
extension AppModel {
    func defaultScene(_ roomID: String) -> DefaultScene? { home.defaults[roomID] ?? defaultsBeingCreated[roomID] }
    func isTemporary(_ roomID: String) -> Bool { temporaryRooms[roomID] != nil }

    // MARK: Hooks from warmth/color changes

    /// Before the first change, saves the room's current state as its default scene.
    func prepareColorChange(_ room: Room) -> Bool {
        guard defaultScene(room.id) == nil, let client else { return true }
        let name = DefaultScene.name(for: room.name)
        let actions = DefaultScene.actions(for: home.lights(in: room), color: nil)
        defaultsBeingCreated[room.id] = DefaultScene(id: "", roomID: room.id, name: name, actions: actions)
        Task {
            do {
                let id = try await client.createScene(name: name, roomID: room.id, actions: actions)
                home.defaults[room.id] = DefaultScene(id: id, roomID: room.id, name: name, actions: actions)
                log.add(.info, "Created default scene \"\(name)\"")
            } catch {
                log.add(.error, "Couldn't create default scene for \(room.name): \(error.localizedDescription)")
            }
            defaultsBeingCreated[room.id] = nil
        }
        return true
    }

    /// After a warmth or color change: temporary unless it matches the default.
    func noteColorChange(_ roomID: String, color: LightColor, wasDefault: Bool) {
        pendingDefaults.remove(roomID)
        if let d = defaultScene(roomID)?.color, d.isClose(to: color) {
            temporaryRooms[roomID] = nil
        } else {
            temporaryRooms[roomID] = color
        }
    }

    // MARK: The Temporary color card

    /// Back to default: recall the room's scene at its current brightness. A room that's
    /// off stays off; its default comes back the next time House Lights turns it on.
    func backToDefault(_ roomID: String) {
        guard let room = room(roomID), let scene = home.defaults[roomID] else { return }
        temporaryRooms[roomID] = nil
        defaultsError = nil
        // The remote follows: its scene goes back to the default too.
        remoteSceneChanged(roomID, color: scene.color)
        if room.isOn {
            recall(scene, in: room, brightness: room.brightness)
        } else {
            pendingDefaults.insert(roomID)
            log.add(.info, "\(room.name) is off: default will apply when it's next turned on")
        }
    }

    /// Set as default: rewrite the room's scene with what the lights show now.
    func setAsDefault(_ roomID: String) {
        guard let room = room(roomID), let client else { return }
        let actions = DefaultScene.actions(for: home.lights(in: room), color: room.color)
        temporaryRooms[roomID] = nil
        pendingDefaults.remove(roomID)
        defaultsError = nil
        let name = DefaultScene.name(for: room.name)
        let existing = home.defaults[roomID]
        home.defaults[roomID] = DefaultScene(id: existing?.id ?? "", roomID: roomID, name: existing?.name ?? name, actions: actions)
        Task {
            do {
                if let existing, !existing.id.isEmpty {
                    try await client.updateScene(id: existing.id, actions: actions)
                } else {
                    let id = try await client.createScene(name: name, roomID: roomID, actions: actions)
                    home.defaults[roomID]?.id = id
                }
                log.add(.info, "Saved \(room.name)'s default")
            } catch {
                defaultsError = "Couldn’t save the default."
                log.add(.error, "Set as default for \(room.name): \(error.localizedDescription)")
            }
        }
    }

    /// Turning on a room whose Back to default was tapped while off: recall its scene.
    func turnOnWithDefault(_ roomID: String) -> Bool {
        guard pendingDefaults.contains(roomID), let room = room(roomID), let scene = home.defaults[roomID] else { return false }
        pendingDefaults.remove(roomID)
        store.zeroDimmed.remove(roomID)
        recall(scene, in: room, brightness: room.brightness >= 1 ? room.brightness : CrownBrightness.backOnLevel)
        return true
    }

    private func recall(_ scene: DefaultScene, in room: Room, brightness: Double) {
        guard let client else { return }
        lastLocalChange[room.id] = Date()
        // Show the default at once.
        for action in scene.actions {
            let id = action.target.rid
            if let m = action.action.color_temperature?.mirek { home.lights[id]?.color = .temperature(mirek: m) }
            if let xy = action.action.color?.xy { home.lights[id]?.color = .xy(XY(x: xy.x, y: xy.y)) }
            home.lights[id]?.isOn = true
        }
        let lights = home.lights(in: room)   // read before update() starts modifying home
        update(room.id) {
            $0.isOn = true
            $0.brightness = brightness
            HomeSnapshot.derive(&$0, from: lights)
        }
        Task {
            do { try await client.recallScene(id: scene.id, brightness: brightness) }
            catch { fail(error) }
        }
    }

    // MARK: Outside changes

    /// Drops the temporary label when a room's color was changed outside the app (Hue app,
    /// a switch, a power cut bringing bulbs back in warm white), and forgets a pending
    /// default if the room was switched on elsewhere.
    func checkTemporaryColors(_ roomIDs: Set<String>, turnedOnOutside: Set<String> = []) {
        var temporary = temporaryRooms
        for id in roomIDs {
            guard let set = temporary[id], let room = room(id), let now = room.color else { continue }
            if !now.isClose(to: set) {
                temporary[id] = nil
                log.add(.info, "\(room.name)'s color changed outside the app; no longer temporary")
            }
        }
        if temporary != temporaryRooms { temporaryRooms = temporary }
        let pending = pendingDefaults.intersection(turnedOnOutside)
        if !pending.isEmpty { pendingDefaults.subtract(pending) }
    }

    /// After a reload: forget rooms that are gone and colors that changed while the app was closed.
    func afterReload() {
        let ids = Set(home.rooms.map(\.id))
        // A room switched on elsewhere (a remote, while the app was closed) is no longer "dimmed to 0".
        let lit = Set(home.rooms.filter(\.isOn).map(\.id))
        if !store.zeroDimmed.isDisjoint(with: lit) { store.zeroDimmed.subtract(lit) }
        temporaryRooms = temporaryRooms.filter { ids.contains($0.key) }
        pendingDefaults = pendingDefaults.intersection(ids)
        checkTemporaryColors(Set(temporaryRooms.keys))
    }
}
