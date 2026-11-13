import Foundation

/// Tools on the Log screen: share the log, save the bridge's raw replies for debugging, and
/// remove every scene the app has made.
extension AppModel {
    /// The log as plain text, oldest first, for sharing.
    var logText: String {
        log.entries.map { "\($0.date.formatted(.iso8601)) \($0.kind.rawValue) \($0.text)" }.joined(separator: "\n")
    }

    /// Where Save bridge replies writes, in the App Group container.
    static var bridgeRepliesURL: URL { AppGroup.containerURL.appending(path: "bridge-replies.json") }

    /// The resource lists worth seeing when something looks wrong at home.
    static let replyResources = ["room", "zone", "grouped_light", "light", "scene", "device", "bridge_home"]

    /// Reads each resource list as the bridge sent it and saves them together as one JSON
    /// object ({"light": <reply>, …}). The replies hold no key or password. Returns the file,
    /// or nil if nothing could be read.
    func saveBridgeReplies() async -> URL? {
        guard let client else { return nil }
        var parts: [String] = []
        for name in Self.replyResources {
            do {
                let data = try await client.rawResource(name)
                parts.append("\"\(name)\": \(String(decoding: data, as: UTF8.self))")
            } catch {
                log.add(.error, "Saving \(name): \(error.localizedDescription)")
            }
        }
        guard !parts.isEmpty else { return nil }
        let url = Self.bridgeRepliesURL
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("{\n\(parts.joined(separator: ",\n"))\n}\n".utf8).write(to: url, options: .atomic)
            log.add(.info, "Saved \(parts.count) bridge replies")
            return url
        } catch {
            log.add(.error, "Saving bridge replies: \(error.localizedDescription)")
            return nil
        }
    }

    /// How many "House Lights…" scenes are on the bridge.
    var ownSceneCount: Int { ownSceneIDs.count }

    private var ownSceneIDs: Set<String> {
        let known = (home.defaults.values.map(\.id) + home.remoteScenes.values.map(\.id) + home.mixScenes.values.map(\.id))
            .filter { !$0.isEmpty }
        return Set(home.ownSceneIDs).union(known)
    }

    /// Deletes every scene the app made — defaults, remote ("Now") and mix scenes — and
    /// forgets the defaults, hybrids and remote rooms that used them. Lights stay as they are;
    /// a dimmer pointed at a "House Lights Now" scene stops doing anything until set again.
    func removeAllScenes() async {
        guard let client else { return }
        let ids = ownSceneIDs
        log.add(.info, "Removing \(ids.count) House Lights scenes")
        var failed = 0
        for id in ids {
            do { try await client.deleteScene(id: id) }
            catch { failed += 1 }   // the client already logged it
        }
        for task in mixTasks.values { task.cancel() }
        for task in remoteSceneTasks.values { task.cancel() }
        home.defaults = [:]
        home.remoteScenes = [:]
        home.mixScenes = [:]
        home.ownSceneIDs = []
        hybrids = [:]
        pendingMix = []
        pendingDefaults = []
        temporaryRooms = [:]
        remoteRooms = []
        log.add(failed == 0 ? .info : .error,
                failed == 0 ? "Removed the scenes" : "Couldn't remove \(failed) of \(ids.count) scenes")
        await reload()
    }
}
