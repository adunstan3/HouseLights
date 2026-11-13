import Foundation

/// A pretend bridge for the simulator. Commands change its in-memory home and come back
/// through the event stream, the way the real bridge echoes changes.
actor MockBridgeClient: BridgeClient {
    private var home: HomeSnapshot
    private var reachable: Bool
    private var pairAttempts = 0
    private var streams: [UUID: AsyncThrowingStream<[HueEvent], any Error>.Continuation] = [:]
    private let latency: Duration
    private let log: LogSink

    init(home: HomeSnapshot = MockHome.sample(), reachable: Bool = true, latency: Duration = .milliseconds(150),
         log: LogSink = .none) {
        self.home = home
        self.reachable = reachable
        self.latency = latency
        self.log = log
    }

    func setReachable(_ value: Bool) {
        reachable = value
        if !value { endStreams() }
    }

    var currentHome: HomeSnapshot { home }
    /// How many event streams are listening (tests wait for one before simulating changes).
    var streamCount: Int { streams.count }

    // MARK: BridgeClient

    func pair(ip: String) async throws -> PairingAttempt {
        try await respond("POST /api")
        pairAttempts += 1
        // Pretend the button is pressed between the first and second attempt.
        if pairAttempts < 2 { return .linkButtonNotPressed }
        return .paired(PairedBridge(ip: ip, applicationKey: "mock-application-key", certificateHash: Data(repeating: 7, count: 32)))
    }

    func fetchHome() async throws -> HomeSnapshot {
        try await respond("GET /clip/v2/resource/{room,zone,grouped_light,light,scene}")
        return home
    }

    func send(_ command: GroupedLightCommand, toGroupedLight id: String) async throws {
        try await respond("PUT /clip/v2/resource/grouped_light/\(id) — \(command.summary)")
        let lightIDs: [String]
        if id == home.allLightsGroupID {
            lightIDs = Array(home.lights.keys)
        } else if let room = home.rooms.first(where: { $0.groupedLightID == id }) {
            lightIDs = room.lightIDs
        } else {
            throw BridgeError.http(404, "no grouped_light \(id)")
        }
        var items: [HueEventItem] = []
        for lid in lightIDs {
            guard var light = home.lights[lid] else { continue }
            if let on = command.on { light.isOn = on }
            if let b = command.brightness { light.brightness = min(max(b, 1), 100) }
            if let m = command.mirek, light.mirekRange != nil {
                light.color = .temperature(mirek: light.mirekRange.map { min(max(m, $0.lowerBound), $0.upperBound) } ?? m)
            }
            if let p = command.xy, let g = light.gamut { light.color = .xy(g.clamp(p)) }
            if command.xy != nil || command.mirek != nil { light.isDynamic = false }   // a color stops a moving palette
            home.lights[lid] = light
            items.append(lightItem(light))
        }
        items += refreshGroups()
        emit(items)
    }

    func createScene(name: String, roomID: String, actions: [HueSceneAction], motion: SceneMotion?) async throws -> String {
        try await respond("POST /clip/v2/resource/scene — \(name)")
        let id = "mock-scene-\(UUID().uuidString.prefix(8))"
        var scene = DefaultScene(id: id, roomID: roomID, name: name, actions: actions)
        scene.apply(motion)
        home.ownSceneIDs.append(id)
        if DefaultScene.isRemoteScene(name) { home.remoteScenes[roomID] = scene }
        else if DefaultScene.isMixScene(name) { home.mixScenes[roomID] = scene }
        else { home.defaults[roomID] = scene }
        return id
    }

    func updateScene(id: String, actions: [HueSceneAction], motion: SceneMotion?) async throws {
        try await respond("PUT /clip/v2/resource/scene/\(id)")
        func change(_ s: inout DefaultScene) {
            s.actions = actions
            s.apply(motion)
        }
        if let roomID = home.remoteScenes.first(where: { $0.value.id == id })?.key { change(&home.remoteScenes[roomID]!); return }
        if let roomID = home.mixScenes.first(where: { $0.value.id == id })?.key { change(&home.mixScenes[roomID]!); return }
        guard let roomID = home.defaults.first(where: { $0.value.id == id })?.key else { throw BridgeError.http(404, "no scene") }
        change(&home.defaults[roomID]!)
    }

    func deleteScene(id: String) async throws {
        try await respond("DELETE /clip/v2/resource/scene/\(id)")
        home.defaults = home.defaults.filter { $0.value.id != id }
        home.remoteScenes = home.remoteScenes.filter { $0.value.id != id }
        home.mixScenes = home.mixScenes.filter { $0.value.id != id }
        home.ownSceneIDs.removeAll { $0 == id }
    }

    func rawResource(_ name: String) async throws -> Data {
        try await respond("GET /clip/v2/resource/\(name)")
        return Data(#"{"errors":[],"data":[],"note":"mock bridge"}"#.utf8)
    }

    func recallScene(id: String, brightness: Double?, dynamic: Bool) async throws {
        try await respond("PUT /clip/v2/resource/scene/\(id) — recall\(dynamic ? " moving" : "")")
        let all = Array(home.defaults.values) + Array(home.remoteScenes.values) + Array(home.mixScenes.values)
        guard let scene = all.first(where: { $0.id == id }) else { throw BridgeError.http(404, "no scene") }
        // Like the bridge: a moving recall, or a scene with auto_dynamic, plays its palette.
        let moving = (dynamic || scene.autoDynamic) && scene.palette.count >= 2
        var items: [HueEventItem] = []
        for action in scene.actions {
            guard var light = home.lights[action.target.rid] else { continue }
            light.isOn = action.action.on?.on ?? true
            light.brightness = brightness ?? action.action.dimming?.brightness ?? light.brightness
            light.isDynamic = moving
            if let m = action.action.color_temperature?.mirek { light.color = .temperature(mirek: m) }
            if let xy = action.action.color?.xy { light.color = .xy(XY(x: xy.x, y: xy.y)) }
            home.lights[light.id] = light
            items.append(lightItem(light))
        }
        items += refreshGroups()
        emit(items)
    }

    nonisolated func events() -> AsyncThrowingStream<[HueEvent], any Error> {
        AsyncThrowingStream { continuation in
            let id = UUID()
            Task { await self.addStream(id, continuation) }
            continuation.onTermination = { _ in Task { await self.removeStream(id) } }
        }
    }

    // MARK: Pretending to be the outside world

    /// Changes a light as if someone used the Hue app or a switch (for checking live updates).
    func simulateOutsideChange() {
        guard let room = home.rooms.filter({ $0.kind == .room }).randomElement() else { return }
        var items: [HueEventItem] = []
        for lid in room.lightIDs {
            guard var light = home.lights[lid] else { continue }
            light.isOn.toggle()
            home.lights[lid] = light
            items.append(lightItem(light))
        }
        items += refreshGroups()
        log(.info, "Mock: outside change to \(room.name)")
        emit(items)
    }

    /// Presses a dimmer switch's On button set to the room's remote scene.
    func simulateRemotePress(roomID: String) async throws {
        guard let scene = home.remoteScenes[roomID] else { throw BridgeError.http(404, "no remote scene") }
        try await recallScene(id: scene.id, brightness: nil, dynamic: false)
    }

    /// Sets a room's color as the Hue app (or a power cut) would.
    func simulateOutsideColor(roomID: String, color: LightColor) {
        guard let room = home.room(roomID) else { return }
        var items: [HueEventItem] = []
        for lid in room.lightIDs {
            guard var light = home.lights[lid] else { continue }
            light.color = color
            home.lights[lid] = light
            items.append(lightItem(light))
        }
        items += refreshGroups()
        emit(items)
    }

    // MARK: Helpers

    private func respond(_ what: String) async throws {
        log(.request, what)
        try await Task.sleep(for: latency)
        guard reachable else {
            log(.error, "\(what): Bridge not reachable (mock)")
            throw BridgeError.unreachable("mock bridge is offline")
        }
        log(.response, "200 \(what)")
    }

    private func addStream(_ id: UUID, _ c: AsyncThrowingStream<[HueEvent], any Error>.Continuation) {
        guard reachable else {
            c.finish(throwing: BridgeError.unreachable("mock bridge is offline"))
            return
        }
        streams[id] = c
        log(.info, "Mock event stream connected")
    }

    private func removeStream(_ id: UUID) { streams[id] = nil }

    private func endStreams() {
        for c in streams.values { c.finish(throwing: BridgeError.unreachable("mock bridge went offline")) }
        streams.removeAll()
    }

    private func emit(_ items: [HueEventItem]) {
        let event = HueEvent(type: "update", data: items)
        Task {
            try? await Task.sleep(for: latency)
            for c in streams.values { c.yield([event]) }
        }
    }

    /// Recomputes every room's on/brightness from its lights, as the bridge does for grouped lights.
    private func refreshGroups() -> [HueEventItem] {
        var items: [HueEventItem] = []
        for i in home.rooms.indices {
            let lights = home.lights(in: home.rooms[i])
            let lit = lights.filter(\.isOn)
            home.rooms[i].isOn = !lit.isEmpty
            if !lit.isEmpty { home.rooms[i].brightness = lit.map(\.brightness).reduce(0, +) / Double(lit.count) }
            HomeSnapshot.derive(&home.rooms[i], from: lights)
            items.append(HueEventItem(id: home.rooms[i].groupedLightID, type: "grouped_light",
                                      on: HueOn(on: home.rooms[i].isOn),
                                      dimming: HueDimming(brightness: home.rooms[i].isOn ? home.rooms[i].brightness : 0)))
        }
        return items
    }

    private func lightItem(_ light: LightState) -> HueEventItem {
        var item = HueEventItem(id: light.id, type: "light", on: HueOn(on: light.isOn), dimming: HueDimming(brightness: light.brightness),
                                dynamics: HueLightDynamics(status: light.isDynamic ? "dynamic_palette" : "none"))
        switch light.color {
        case .temperature(let m)?: item.color_temperature = HueColorTemperatureDTO(mirek: m, mirek_valid: true)
        case .xy(let p)?:
            item.color = HueEventColor(xy: HueXY(x: p.x, y: p.y))
            item.color_temperature = HueColorTemperatureDTO(mirek: nil, mirek_valid: false)
        case nil: break
        }
        return item
    }
}
