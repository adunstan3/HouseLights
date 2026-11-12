import Foundation

/// Everything the app knows about the bridge: rooms and zones (as tiles), their lights,
/// the "House Lights –" default scenes, and the all-lights group.
nonisolated struct HomeSnapshot: Sendable, Equatable {
    /// Rooms first, then zones, in bridge order. The grid applies the user's order on top.
    var rooms: [Room] = []
    var lights: [String: LightState] = [:]
    /// Default scene per room id.
    var defaults: [String: DefaultScene] = [:]
    /// "House Lights Now" scene per room (what its remote turns it on with).
    var remoteScenes: [String: DefaultScene] = [:]
    /// "House Lights Mix" scene per room (the working scene for hybrids).
    var mixScenes: [String: DefaultScene] = [:]
    /// The `bridge_home` grouped light, which switches every light at once.
    var allLightsGroupID: String?

    static let empty = HomeSnapshot()

    func room(_ id: String) -> Room? { rooms.first { $0.id == id } }
    func lights(in room: Room) -> [LightState] { room.lightIDs.compactMap { lights[$0] } }

    // MARK: Building from the bridge's resources

    init() {}

    init(rooms roomDTOs: [HueGroupDTO], zones: [HueGroupDTO], groupedLights: [HueGroupedLightDTO],
         lights lightDTOs: [HueLightDTO], scenes: [HueSceneDTO]) {
        for l in lightDTOs { lights[l.id] = LightState(l) }
        let groups = Dictionary(groupedLights.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        allLightsGroupID = groupedLights.first { $0.owner.rtype == "bridge_home" }?.id

        func make(_ dto: HueGroupDTO, kind: RoomKind) -> Room? {
            // An empty room has no grouped_light; there's nothing to control, so skip it.
            guard let gid = dto.services.first(where: { $0.rtype == "grouped_light" })?.rid else { return nil }
            let deviceIDs = Set(dto.children.filter { $0.rtype == "device" }.map(\.rid))
            let directLights = dto.children.filter { $0.rtype == "light" }.map(\.rid)
            let viaDevices = lightDTOs.filter { deviceIDs.contains($0.owner.rid) }.map(\.id)
            let group = groups[gid]
            let ids = directLights + viaDevices
            let isOn = group?.on?.on ?? false
            // While a room is off its grouped_light can report brightness 0; keep the level its
            // bulbs will come back at (their own last brightness) instead.
            let lastLevel = ids.compactMap { lights[$0]?.brightness }.max()
            var room = Room(id: dto.id, kind: kind, name: dto.metadata.name ?? "Room",
                            archetype: dto.metadata.archetype ?? "other", groupedLightID: gid,
                            lightIDs: ids, isOn: isOn,
                            brightness: isOn ? (group?.dimming?.brightness ?? lastLevel ?? 0) : (lastLevel ?? group?.dimming?.brightness ?? 0))
            HomeSnapshot.derive(&room, from: room.lightIDs.compactMap { lights[$0] })
            return room
        }
        rooms = roomDTOs.compactMap { make($0, kind: .room) } + zones.compactMap { make($0, kind: .zone) }

        let roomIDs = Set(rooms.map(\.id))
        for s in scenes where roomIDs.contains(s.group.rid) {
            let name = s.metadata.name ?? ""
            var scene = DefaultScene(id: s.id, roomID: s.group.rid, name: name, actions: s.actions)
            scene.palette = s.palette?.color.map { XY(x: $0.color.xy.x, y: $0.color.xy.y) } ?? []
            scene.autoDynamic = s.auto_dynamic ?? false
            if DefaultScene.isRemoteScene(name) { remoteScenes[s.group.rid] = scene }
            else if DefaultScene.isMixScene(name) { mixScenes[s.group.rid] = scene }
            else if DefaultScene.isDefaultScene(name) { defaults[s.group.rid] = scene }
        }
    }

    /// Fills a room's color, gamut and warmth range from its lights.
    static func derive(_ room: inout Room, from lights: [LightState]) {
        let lit = lights.filter(\.isOn)
        let shown = (lit.isEmpty ? lights : lit).compactMap(\.color)
        room.color = shown.mostCommon
        var distinct: [LightColor] = []
        for c in shown where !distinct.contains(where: { $0.isClose(to: c) }) { distinct.append(c) }
        room.mixColors = distinct.count >= 2 ? Array(distinct.prefix(4)) : nil
        room.isMoving = lights.contains(where: \.isDynamic) ? true : nil
        room.gamut = lights.compactMap(\.gamut).mostCommon
        let ranges = lights.compactMap(\.mirekRange)
        if let lo = ranges.map(\.lowerBound).max(), let hi = ranges.map(\.upperBound).min(), lo <= hi {
            room.mirekRange = lo...hi
        } else {
            room.mirekRange = ranges.first
        }
    }

    // MARK: Live updates

    /// Applies one event-stream item. Returns the ids of rooms whose tiles changed.
    @discardableResult
    mutating func apply(_ item: HueEventItem) -> Set<String> {
        switch item.type {
        case "grouped_light":
            guard let i = rooms.firstIndex(where: { $0.groupedLightID == item.id }) else { return [] }
            if let on = item.on { rooms[i].isOn = on.on }
            // An off room keeps its last brightness (the group may report 0 while off).
            if let d = item.dimming, rooms[i].isOn { rooms[i].brightness = d.brightness }
            return [rooms[i].id]
        case "light":
            guard var light = lights[item.id] else { return [] }
            if let on = item.on { light.isOn = on.on }
            if let d = item.dimming { light.brightness = d.brightness }
            if let d = item.dynamics?.status { light.isDynamic = d == "dynamic_palette" }
            if let ct = item.color_temperature, let m = ct.mirek, ct.mirek_valid ?? true {
                light.color = .temperature(mirek: m)
            } else if let c = item.color {
                light.color = .xy(XY(x: c.xy.x, y: c.xy.y))
            }
            lights[item.id] = light
            var changed: Set<String> = []
            for i in rooms.indices where rooms[i].lightIDs.contains(item.id) {
                HomeSnapshot.derive(&rooms[i], from: rooms[i].lightIDs.compactMap { lights[$0] })
                changed.insert(rooms[i].id)
            }
            return changed
        default:
            return []
        }
    }

    /// Whether an event needs a full reload (rooms, lights or scenes added, removed or renamed).
    static func needsReload(_ event: HueEvent) -> Bool {
        let structural: Set<String> = ["room", "zone", "light", "grouped_light", "scene", "device"]
        if event.type == "add" || event.type == "delete" {
            return event.data.contains { structural.contains($0.type) }
        }
        return event.data.contains { ($0.type == "room" || $0.type == "zone") && $0.metadata != nil }
    }
}
