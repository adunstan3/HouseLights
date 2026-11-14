import Foundation

/// Saved whole-house configurations (grid › bookmark). Saving records every room shown on
/// the grid, light by light; loading puts them back. Hidden rooms are neither saved nor
/// changed.
extension AppModel {
    /// The house as it is now, for saving.
    func currentConfig(named name: String, id: UUID = UUID()) -> HouseConfig {
        HouseConfig(id: id, name: name, savedAt: .now, rooms: rooms.map { room in
            RoomConfig(roomID: room.id, roomName: room.name, isOn: room.isOn,
                       lights: home.lights(in: room).map(LightSetting.init),
                       hybrid: hybrids[room.id], temporary: temporaryRooms[room.id])
        })
    }

    /// Save current lights: a new configuration at the top of the list.
    @discardableResult
    func saveConfig(named text: String) -> HouseConfig? {
        guard let name = HouseConfig.cleanName(text) else { return nil }
        let config = currentConfig(named: name)
        houseConfigs.insert(config, at: 0)
        log.add(.info, "Saved configuration \(name) (\(config.rooms.count) rooms)")
        return config
    }

    func renameConfig(_ id: UUID, to text: String) {
        guard let name = HouseConfig.cleanName(text), let i = houseConfigs.firstIndex(where: { $0.id == id }) else { return }
        houseConfigs[i].name = name
    }

    /// Replaces a configuration's lights with the house as it is now (keeping its name).
    func overwriteConfig(_ id: UUID) {
        guard let i = houseConfigs.firstIndex(where: { $0.id == id }) else { return }
        houseConfigs[i] = currentConfig(named: houseConfigs[i].name, id: id)
        log.add(.info, "Saved current lights over \(houseConfigs[i].name)")
    }

    func deleteConfig(_ id: UUID) {
        houseConfigs.removeAll { $0.id == id }
    }

    /// Loads a configuration. Rooms saved off are turned off. Each lit room gets its saved
    /// lights written into its "House Lights Mix" working scene, which is then recalled: one
    /// write and one recall per room puts every light back exactly (a moving mix keeps moving).
    /// The grid shows the result at once; rooms no longer on the bridge, or hidden, are skipped.
    func loadConfig(_ id: UUID) {
        guard let config = houseConfigs.first(where: { $0.id == id }) else { return }
        log.add(.info, "Loading configuration \(config.name)")
        var mixes: [(roomID: String, actions: [HueSceneAction], motion: SceneMotion, dynamic: Bool)] = []
        for saved in config.rooms {
            guard let room = room(saved.roomID), !hiddenRooms.contains(room.id) else { continue }
            mixTasks[room.id]?.cancel()
            hybrids[room.id] = saved.hybrid
            temporaryRooms[room.id] = saved.temporary
            pendingDefaults.remove(room.id)
            pendingMix.remove(room.id)
            store.zeroDimmed.remove(room.id)
            lastLocalChange[room.id] = Date()

            guard saved.isOn else {
                if room.isOn {
                    update(room.id) { $0.isOn = false }
                    enqueue(.power(false), for: room)
                    remoteSceneChanged(room.id)
                }
                continue
            }

            let moving = saved.hybrid?.moving == true
            let lights = saved.lights.filter { home.lights[$0.id] != nil }
            var actions: [HueSceneAction] = []
            for setting in lights {
                guard let light = home.lights[setting.id] else { continue }
                actions.append(setting.sceneAction(for: light))
                home.lights[setting.id]?.isOn = setting.isOn
                home.lights[setting.id]?.brightness = setting.brightness
                if let color = setting.color { home.lights[setting.id]?.color = color }
                home.lights[setting.id]?.isDynamic = moving && setting.isOn
            }
            let roomLights = home.lights(in: room)
            let lit = lights.filter(\.isOn).map(\.brightness)
            let level = lit.isEmpty ? 100 : lit.reduce(0, +) / Double(lit.count)
            update(room.id) {
                HomeSnapshot.derive(&$0, from: roomLights)
                $0.isOn = !lit.isEmpty       // on/off comes from the room's group, so set it here
                if !lit.isEmpty { $0.brightness = level }
            }
            // A still configuration writes an empty palette, so a mix that moved before stops.
            let motion = saved.hybrid.map {
                SceneMotion(colors: $0.colors.map { $0.xy(in: room.gamut) }, brightness: level, moving: $0.moving, speed: $0.pace.value)
            } ?? SceneMotion(colors: [], brightness: level, moving: false)
            mixes.append((room.id, actions, motion, moving))
            remoteSceneChanged(room.id)
        }
        configTask?.cancel()
        configTask = Task { [weak self] in
            for mix in mixes where !Task.isCancelled {
                await self?.writeMix(mix.roomID, actions: mix.actions, motion: mix.motion,
                                     recall: MixRecall(brightness: nil, dynamic: mix.dynamic))
            }
        }
    }
}
