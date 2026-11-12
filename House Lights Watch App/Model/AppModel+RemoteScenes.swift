import Foundation

/// Remote scenes: for rooms with a Hue dimmer switch, the watch keeps a scene called
/// "House Lights Now – <room>" up to date with the last color, warmth and brightness it set.
/// Point the dimmer's On button at that scene (in the Hue app) and the remote turns the room
/// on in whatever the watch last chose. The real default stays in "House Lights – <room>".
extension AppModel {
    func hasRemoteScene(_ roomID: String) -> Bool { remoteRooms.contains(roomID) }

    /// Settings › Remote scenes. Turning it on creates the scene from the room's current look.
    /// Turning it off stops updating it (the scene stays, in case a remote still uses it).
    func setRemoteScene(_ roomID: String, enabled: Bool) {
        if enabled {
            remoteRooms.insert(roomID)
            Task { await writeRemoteScene(roomID) }
        } else {
            remoteRooms.remove(roomID)
            remoteSceneTasks[roomID]?.cancel()
            log.add(.info, "Stopped updating the remote scene for \(room(roomID)?.name ?? roomID)")
        }
    }

    /// Called after every change the watch makes to a room. Saves the scene once the room has
    /// been left alone for `remoteSceneDelay`, so dragging a slider is one write, not dozens.
    /// The lights themselves are changed first, exactly as before.
    func remoteSceneChanged(_ roomID: String, color: LightColor? = nil) {
        guard remoteRooms.contains(roomID) else { return }
        remoteSceneTasks[roomID]?.cancel()
        remoteSceneTasks[roomID] = Task { [weak self] in
            try? await Task.sleep(for: self?.remoteSceneDelay ?? .seconds(1.5))
            guard !Task.isCancelled else { return }
            await self?.writeRemoteScene(roomID, color: color)
        }
    }

    /// Writes the room's current look (or `color`) into its remote scene, creating it if needed.
    func writeRemoteScene(_ roomID: String, color: LightColor? = nil) async {
        guard let client, let room = room(roomID) else { return }
        let actions = DefaultScene.actions(for: home.lights(in: room), color: color ?? room.color,
                                           brightness: room.brightness >= 1 ? room.brightness : nil)
        do {
            if let existing = home.remoteScenes[roomID], !existing.id.isEmpty {
                try await client.updateScene(id: existing.id, actions: actions)
                home.remoteScenes[roomID]?.actions = actions
            } else {
                let name = DefaultScene.remoteName(for: room.name)
                let id = try await client.createScene(name: name, roomID: roomID, actions: actions)
                home.remoteScenes[roomID] = DefaultScene(id: id, roomID: roomID, name: name, actions: actions)
                log.add(.info, "Created remote scene \"\(name)\"")
            }
        } catch {
            log.add(.error, "Remote scene for \(room.name): \(error.localizedDescription)")
        }
    }
}
