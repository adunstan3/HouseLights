import Foundation

/// Hybrid color schemes: several saved colors spread over a room's bulbs, one per bulb,
/// optionally moving (the bridge morphs the lights between them). Shown through a working
/// scene per room, "House Lights Mix – <room>": its per-light actions hold the colors, its
/// palette holds them for moving, and `auto_dynamic` keeps it moving when recalled.
extension AppModel {
    /// The room's color bulbs (white-only bulbs can't take a color).
    func colorBulbs(_ room: Room) -> [LightState] { home.lights(in: room).filter { $0.gamut != nil } }

    /// Whether this many colors must move in this room (more colors than bulbs).
    func mixMustMove(colors: Int, roomID: String) -> Bool {
        guard let room = room(roomID) else { return false }
        return Hybrid.mustMove(colors: colors, bulbs: colorBulbs(room).count)
    }

    /// Shows a hybrid in a room. An off room stays off: the mix is saved and shown the next
    /// time the app turns the room on.
    func setHybrid(_ colors: [WheelColor], moving: Bool, roomID: String) {
        guard let room = room(roomID), colors.count >= 2 else { return }
        let hybrid = Hybrid(colors: Array(colors.prefix(Hybrid.maxColors)),
                            moving: moving || mixMustMove(colors: colors.count, roomID: roomID))
        _ = prepareColorChange(room)
        hybrids[roomID] = hybrid
        pendingDefaults.remove(roomID)
        if hybridMatchesDefault(hybrid, room: room) { temporaryRooms[roomID] = nil }
        else { temporaryRooms[roomID] = .xy(hybrid.colors[0].xy(in: room.gamut)) }

        // Show it at once: each bulb its color.
        let assignments = hybrid.assignments(lightIDs: colorBulbs(room).map(\.id), gamut: room.gamut)
        for (id, xy) in assignments {
            home.lights[id]?.color = .xy(xy)
            home.lights[id]?.isDynamic = hybrid.moving && room.isOn
        }
        let lights = home.lights(in: room)
        update(roomID) { HomeSnapshot.derive(&$0, from: lights) }
        lastLocalChange[roomID] = Date()

        if room.isOn { pendingMix.remove(roomID) } else { pendingMix.insert(roomID) }
        mixTasks[roomID]?.cancel()
        mixTasks[roomID] = Task { [weak self] in
            await self?.writeMixScene(roomID, hybrid: hybrid, recall: room.isOn)
        }
        remoteSceneChanged(roomID)
    }

    /// Writes the room's mix scene (creating it the first time) and, if `recall`, shows it.
    func writeMixScene(_ roomID: String, hybrid: Hybrid, recall: Bool) async {
        guard let client, let room = room(roomID) else { return }
        let (actions, motion) = mixScene(for: room, hybrid: hybrid)
        do {
            let id: String
            if let existing = home.mixScenes[roomID], !existing.id.isEmpty {
                try await client.updateScene(id: existing.id, actions: actions, motion: motion)
                id = existing.id
            } else {
                id = try await client.createScene(name: DefaultScene.mixName(for: room.name), roomID: roomID,
                                                  actions: actions, motion: motion)
                log.add(.info, "Created mix scene for \(room.name)")
            }
            var scene = DefaultScene(id: id, roomID: roomID, name: DefaultScene.mixName(for: room.name), actions: actions)
            scene.palette = motion.colors
            scene.autoDynamic = motion.moving
            home.mixScenes[roomID] = scene
            if recall, !Task.isCancelled {
                lastLocalChange[roomID] = Date()
                try await client.recallScene(id: id, brightness: room.brightness >= 1 ? room.brightness : nil, dynamic: hybrid.moving)
            }
        } catch {
            fail(error)
            log.add(.error, "Hybrid for \(room.name): \(error.localizedDescription)")
        }
    }

    /// Per-light actions and the palette for a hybrid in this room, at its brightness.
    func mixScene(for room: Room, hybrid: Hybrid) -> ([HueSceneAction], SceneMotion) {
        let level: Double? = store.zeroDimmed.contains(room.id) ? CrownBrightness.backOnLevel
            : (room.brightness >= 1 ? room.brightness : nil)
        let assignments = hybrid.assignments(lightIDs: colorBulbs(room).map(\.id), gamut: room.gamut)
        let actions = DefaultScene.actions(for: home.lights(in: room), assignments: assignments, brightness: level)
        let motion = SceneMotion(colors: hybrid.colors.map { $0.xy(in: room.gamut) },
                                 brightness: level ?? 100, moving: hybrid.moving)
        return (actions, motion)
    }

    /// A single color or warmth replaces the hybrid.
    func clearHybrid(_ roomID: String) {
        hybrids[roomID] = nil
        pendingMix.remove(roomID)
        mixTasks[roomID]?.cancel()
    }

    /// Turning on a room whose hybrid was chosen while it was off: recall the mix scene.
    func turnOnWithMix(_ roomID: String) -> Bool {
        guard pendingMix.contains(roomID), let hybrid = hybrids[roomID], let room = room(roomID),
              let scene = home.mixScenes[roomID], let client else { return false }
        pendingMix.remove(roomID)
        store.zeroDimmed.remove(roomID)
        update(roomID) { $0.isOn = true }
        lastLocalChange[roomID] = Date()
        Task {
            do { try await client.recallScene(id: scene.id, brightness: room.brightness >= 1 ? room.brightness : nil, dynamic: hybrid.moving) }
            catch { fail(error) }
        }
        return true
    }

    /// Whether the room's default scene shows the same colors.
    func hybridMatchesDefault(_ hybrid: Hybrid, room: Room) -> Bool {
        guard let defaults = defaultScene(room.id)?.colors, defaults.count == hybrid.colors.count else { return false }
        let mine = hybrid.colors.map { LightColor.xy($0.xy(in: room.gamut)) }
        return mine.allSatisfy { c in defaults.contains { $0.isClose(to: c) } }
    }

    /// Whether a room still shows its app-set hybrid: moving, or every lit color bulb showing
    /// one of the hybrid's colors.
    func stillShowsHybrid(_ room: Room, _ hybrid: Hybrid) -> Bool {
        if room.isMoving == true { return true }
        let mine = hybrid.colors.map { LightColor.xy($0.xy(in: room.gamut)) }
        let shown = colorBulbs(room).filter(\.isOn).compactMap(\.color)
        return !shown.isEmpty && shown.allSatisfy { c in mine.contains { $0.isClose(to: c) } }
    }
}
