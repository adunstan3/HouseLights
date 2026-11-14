import AppIntents
import Foundation
import Observation
import WidgetKit

/// The app's state: connection to the bridge, the home (rooms, zones, lights), and the
/// live event stream. Control actions live in the AppModel+… extensions.
@MainActor @Observable
final class AppModel {
    enum Phase: Equatable {
        case starting
        case unpaired
        case loading
        case ready
        case unreachable(String)
    }

    private(set) var phase: Phase = .starting
    var home: HomeSnapshot = .empty
    private(set) var credentials: BridgeCredentials?
    private(set) var streamConnected = false
    /// Keeps the first-launch Bridge screen up after pairing, to show Paired and Show rooms.
    var showPairedConfirmation = false
    /// A short message at the bottom of the screen when the bridge refuses a change.
    private(set) var notice: String?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?

    let log: BridgeLog
    let store: SharedStore
    /// Where Save bridge replies writes (tests use a temporary file).
    @ObservationIgnored var bridgeRepliesURL = AppModel.defaultRepliesURL
    let environment: BridgeEnvironment
    private(set) var client: (any BridgeClient)?

    private var streamTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    /// How often the backup poll reads the lights' state while the app is open: every 3 s
    /// until the event stream is seen delivering, then every 20 s (saves watch battery).
    var pollInterval: Duration = .seconds(3)
    var slowPollInterval: Duration = .seconds(20)
    /// When the event stream last delivered an update on the current connection.
    @ObservationIgnored var lastStreamUpdate: Date?
    @ObservationIgnored private var widgetTask: Task<Void, Never>?

    /// True once live updates are arriving on the current event-stream connection.
    var liveUpdatesFlowing: Bool { streamConnected && lastStreamUpdate != nil }
    private var reloadTask: Task<Void, Never>?
    /// When the app last sent something to each room, so stream echoes aren't mistaken for outside changes.
    var lastLocalChange: [String: Date] = [:]
    /// The newest grouped_light update per room that arrived while the room was settling.
    @ObservationIgnored var heldUpdates: [String: HueEventItem] = [:]
    /// Default scenes being created on the bridge (used for comparisons until the bridge answers).
    var defaultsBeingCreated: [String: DefaultScene] = [:]
    /// The last error from a defaults action, shown on the Room screen.
    var defaultsError: String?
    @ObservationIgnored lazy var sender = CommandSender { [weak self] id, command in
        await self?.deliver(command, to: id)
    }

    init(environment: BridgeEnvironment, store: SharedStore = SharedStore(), log: BridgeLog) {
        self.environment = environment
        self.store = store
        self.log = log
        let cached = store.lastKnownRooms
        if !cached.isEmpty { home.rooms = cached }
        gridOrder = store.gridOrder
        temporaryRooms = store.temporaryRooms
        pendingDefaults = store.pendingDefaults
        savedSwatches = store.savedSwatches
        remoteRooms = store.remoteRooms
        hybrids = store.hybrids
        pendingMix = store.pendingMix
        savedArrangement = store.gridArrangement
        hiddenRooms = store.hiddenRooms
    }

    /// The user's grid order (room ids), kept here so the grid redraws when Arrange changes it.
    var gridOrder: [String] = [] { didSet { store.gridOrder = gridOrder } }
    /// Rooms showing a temporary color (with the color set). Observed, so the Temporary
    /// color card appears the moment a change makes a room temporary; saved to the App Group.
    var temporaryRooms: [String: LightColor] = [:] { didSet { store.temporaryRooms = temporaryRooms } }
    /// Rooms whose Back to default was tapped while off.
    var pendingDefaults: Set<String> = [] { didSet { store.pendingDefaults = pendingDefaults } }
    /// The hybrid the app last showed in each room (several colors, maybe moving).
    var hybrids: [String: Hybrid] = [:] { didSet { store.hybrids = hybrids } }
    /// Rooms whose hybrid was chosen while off; shown when the app next turns them on.
    var pendingMix: Set<String> = [] { didSet { store.pendingMix = pendingMix } }
    @ObservationIgnored var mixTasks: [String: Task<Void, Never>] = [:]
    /// Rooms whose "House Lights Now" remote scene the watch keeps up to date.
    var remoteRooms: Set<String> = [] { didSet { store.remoteRooms = remoteRooms } }
    @ObservationIgnored var remoteSceneTasks: [String: Task<Void, Never>] = [:]
    /// How long a room must be left alone before its remote scene is saved.
    @ObservationIgnored var remoteSceneDelay: Duration = .seconds(1.5)
    /// Colors pinned on the Color wheel screen (newest first), shared by every room.
    var savedSwatches: [SavedSwatch] = [] { didSet { store.savedSwatches = savedSwatches } }

    /// Rooms hidden from the grid (dragged to Hidden rooms in Arrange). The grid, the Crown
    /// and All off leave them alone; Siri and the widget still reach them.
    var hiddenRooms: Set<String> = [] { didSet { store.hiddenRooms = hiddenRooms } }

    /// Where each room sits on the grid (saved by Arrange; nil until then).
    var savedArrangement: GridArrangement? { didSet { store.gridArrangement = savedArrangement } }

    /// The grid's arrangement: saved spots kept, new rooms in the first free spot.
    var arrangement: GridArrangement {
        let ids = GridOrder.apply(gridOrder, to: home.rooms.filter { $0.kind == .room && !hiddenRooms.contains($0.id) }).map(\.id)
        return GridArrangement.make(roomIDs: ids, saved: savedArrangement)
    }

    /// The grid's tiles: Hue rooms (not zones, not hidden), top-left to bottom-right.
    var rooms: [Room] { arrangement.readingOrder.compactMap { home.room($0) } }

    /// Hidden rooms that are still on the bridge, by name.
    var hiddenRoomList: [Room] {
        home.rooms.filter { $0.kind == .room && hiddenRooms.contains($0.id) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Every room: the grid's, then the hidden ones (Settings lists that aren't the grid).
    var allRooms: [Room] { rooms + hiddenRoomList }

    /// What the grid's Crown and All off act on: rooms and zones, less the hidden rooms.
    var gridControlledRooms: [Room] { home.rooms.filter { !hiddenRooms.contains($0.id) } }

    var isActive = false

    // MARK: Connecting

    func start() async {
        removeStaleBridgeReplies()
        switch environment.loadCredentials() {
        case .none:
            credentials = nil
            phase = .unpaired
            log.add(.info, "Not paired: showing the Bridge screen")
        case .missingPin(let ip):
            // A key without its certificate pin: send nothing (the key would go to whatever
            // answers at that IP) until the bridge is paired again.
            credentials = nil
            client = nil
            log.add(.error, "No certificate pin saved for the bridge at \(ip); nothing sent. Re-pair in Settings › Bridge.")
            fail(BridgeError.pinMissing)
        case .paired(let saved):
            credentials = saved
            client = environment.makeClient(saved, log.sink)
            await reload()
        }
    }

    /// Reads everything from the bridge again (Try again, launch, structural events).
    func reload() async {
        guard let client else { await start(); return }
        if home.rooms.isEmpty || phase != .ready { phase = .loading }
        let started = Date()
        do {
            var fresh = try await client.fetchHome()
            // A room changed in the app while this read was in flight keeps its new state: the
            // reply was taken before the change and would put the tile back (tap a light right
            // after reopening the app, and the tile stayed lit while the light went off).
            // Check again once things settle, so the tile ends up matching the bridge.
            let changed = Set(lastLocalChange.filter { $0.value >= started }.keys)
            if !changed.isEmpty {
                for i in fresh.rooms.indices {
                    guard changed.contains(fresh.rooms[i].id), let mine = home.room(fresh.rooms[i].id) else { continue }
                    fresh.rooms[i].isOn = mine.isOn
                    fresh.rooms[i].brightness = mine.brightness
                    fresh.rooms[i].color = mine.color
                }
                scheduleReload(after: .seconds(Self.settleTime + 0.5))
            }
            home = fresh
            store.lastKnownRooms = fresh.rooms
            phase = .ready
            log.add(.info, "Loaded \(fresh.rooms.filter { $0.kind == .room }.count) rooms, \(fresh.rooms.filter { $0.kind == .zone }.count) zones, \(fresh.lights.count) lights")
            afterReload()
            if isActive { startEventStream(); startPolling() }
            // Siri learns the rooms' Hue names; the widget picks up their state.
            if !RuntimeEnvironment.isTesting { HouseLightsShortcuts.updateAppShortcutParameters() }
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            fail(error)
        }
    }

    func fail(_ error: any Error) {
        let bridgeError = error as? BridgeError ?? .unreachable(error.localizedDescription)
        if bridgeError.isUnreachable || bridgeError.needsRepair {
            phase = .unreachable(bridgeError.localizedDescription)
            stopEventStream()
        } else if phase == .ready {
            show(bridgeError == .rateLimited ? "The bridge is busy. Try again in a moment."
                                             : "The bridge didn’t accept that change.")
        }
    }

    /// Shows a notice for three seconds (details are in the Bridge log).
    func show(_ message: String) {
        notice = message
        noticeTask?.cancel()
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { notice = nil }
        }
    }

    /// Called after a successful pairing on the Bridge screen. Throws if the key and its
    /// certificate pin couldn't both be saved (then nothing is kept).
    func didPair(_ paired: PairedBridge) async throws {
        _ = try environment.saveCredentials(paired, log.sink)
        log.add(.info, "Saved key and certificate pin for bridge at \(paired.ip)")
        client = nil
        home = .empty
        await start()
    }

    /// Forgets the key, its certificate pin and the bridge's IP, and deletes the files that
    /// hold the home's names (the Bridge log and saved bridge replies).
    func forgetBridge() {
        stopEventStream()
        environment.forgetCredentials()
        store.bridgeIP = nil
        credentials = nil
        client = nil
        phase = .unpaired
        log.erase()
        try? FileManager.default.removeItem(at: bridgeRepliesURL)
    }

    // MARK: App lifecycle

    func becameActive() {
        isActive = true
        // Siri or the widget may have changed these while the app was in the background.
        temporaryRooms = store.temporaryRooms
        pendingDefaults = store.pendingDefaults
        guard phase == .ready else { return }
        Task { await reload() }   // catch up on anything missed while inactive
    }

    func becameInactive() {
        isActive = false
        stopEventStream()
        log.saveNow()
        WidgetCenter.shared.reloadAllTimelines()   // show what the app left the lights at
    }

    // MARK: Event stream

    /// Keeps one connection to /eventstream/clip/v2 while the app is open, reconnecting
    /// with a growing delay if it drops.
    func startEventStream() {
        guard streamTask == nil, let client else { return }
        streamTask = Task { [weak self] in
            var delay: Duration = .seconds(1)
            while !Task.isCancelled {
                var received = 0
                do {
                    self?.streamConnected = true
                    for try await events in client.events() {
                        guard let self else { return }
                        if !self.streamConnected { self.streamConnected = true; delay = .seconds(1) }
                        received += 1
                        self.lastStreamUpdate = Date()
                        // Says in the log whether live updates really arrive on this watch.
                        if received == 1 { self.log.add(.event, "Event stream: first update received") }
                        self.apply(events)
                    }
                } catch {}
                guard let self, !Task.isCancelled else { return }
                self.streamConnected = false
                self.lastStreamUpdate = nil
                self.log.add(.info, "Event stream dropped after \(received) updates; reconnecting in \(delay.components.seconds) s")
                try? await Task.sleep(for: delay)
                delay = min(delay * 2, .seconds(30))
            }
        }
    }

    func stopEventStream() {
        streamTask?.cancel()
        streamTask = nil
        streamConnected = false
        stopPolling()
    }

    // MARK: Backup polling

    /// While the app is open, reads the lights' state every few seconds as well, so changes
    /// from remotes, switches and the Hue app show up even if the event stream isn't
    /// delivering. Quiet in the log unless a read fails.
    func startPolling() {
        guard pollTask == nil, let client else { return }
        pollTask = Task { [weak self] in
            var failures = 0
            while !Task.isCancelled {
                // Wait the short or long interval; the long wait is cut short if the stream stops.
                let slow = self?.liveUpdatesFlowing ?? false
                let wait = slow ? (self?.slowPollInterval ?? .seconds(20)) : (self?.pollInterval ?? .seconds(3))
                var waited: Duration = .zero
                while waited < wait, !Task.isCancelled {
                    let step = min(.seconds(1), wait - waited)
                    try? await Task.sleep(for: step)
                    waited += step
                    if slow, self?.liveUpdatesFlowing == false { break }
                }
                guard let self, !Task.isCancelled, self.phase == .ready else { continue }
                do {
                    let states = try await client.fetchStates()
                    if !Task.isCancelled { self.apply(states) }
                    failures = 0
                } catch {
                    failures += 1
                    if failures == 3 { self.fail(error) }   // a few misses in a row: Bridge not reachable
                }
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Applies polled states to every room that isn't settling after a change in the app.
    func apply(_ states: LiveStates) {
        let settling = Set(home.rooms.filter { isSettling($0) }.map(\.id))
        let busyLights = Set(home.rooms.filter { settling.contains($0.id) }.flatMap(\.lightIDs))
        var changed: Set<String> = []
        for (id, light) in states.lights where !busyLights.contains(id) && home.lights[id] != light {
            home.lights[id] = light
            for room in home.rooms where room.lightIDs.contains(id) { changed.insert(room.id) }
        }
        for i in home.rooms.indices where !settling.contains(home.rooms[i].id) {
            var room = home.rooms[i]
            if let g = states.groups[room.groupedLightID] {
                room.isOn = g.on
                if g.on, let b = g.brightness { room.brightness = b }   // off: keep the last level
            }
            if changed.contains(room.id) { HomeSnapshot.derive(&room, from: home.lights(in: room)) }
            if room != home.rooms[i] {
                home.rooms[i] = room
                changed.insert(room.id)
            }
        }
        if !changed.isEmpty {
            store.lastKnownRooms = home.rooms
            roomsChangedFromStream(changed)
        }
    }

    func apply(_ events: [HueEvent]) {
        var changed: Set<String> = []
        for event in events {
            if HomeSnapshot.needsReload(event) { scheduleReload() }
            guard event.type == "update" else { continue }
            for item in event.data {
                if item.type == "grouped_light", let room = home.rooms.first(where: { $0.groupedLightID == item.id }),
                   isSettling(room) {
                    hold(item, for: room)
                    continue
                }
                changed.formUnion(home.apply(item))
            }
        }
        if !changed.isEmpty {
            store.lastKnownRooms = home.rooms
            roomsChangedFromStream(changed)
        }
    }

    // MARK: Settling after a local change

    /// How long after the app changes a room its own state wins over live updates. The bridge
    /// echoes intermediate and older states (bulbs switch one by one; an earlier command's
    /// update can arrive late), which made a tapped tile flash off → on → off.
    static let settleTime: TimeInterval = 2

    func isSettling(_ room: Room) -> Bool {
        sender.isPending(room.groupedLightID)
            || Date().timeIntervalSince(lastLocalChange[room.id] ?? .distantPast) < Self.settleTime
    }

    /// Keeps the newest update that arrived while settling and applies it once the room has
    /// settled, so the tile ends up matching the bridge even if no further update comes.
    private func hold(_ item: HueEventItem, for room: Room) {
        heldUpdates[room.id] = item
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.settleTime + 0.1))
            guard let self, let held = self.heldUpdates[room.id], let now = self.home.room(room.id),
                  !self.isSettling(now) else { return }
            self.heldUpdates[room.id] = nil
            if !self.home.apply(held).isEmpty { self.store.lastKnownRooms = self.home.rooms }
        }
    }

    /// Refreshes the Smart Stack widget about 2 s after the last change, so it shows what the
    /// lights are doing without a reload for every step of a Crown turn.
    func scheduleWidgetRefresh() {
        widgetTask?.cancel()
        widgetTask = Task {
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { WidgetCenter.shared.reloadAllTimelines() }
        }
    }

    /// Bookkeeping after live updates from outside the app (ignoring echoes of our own commands
    /// for 3 s): a room switched on elsewhere is no longer "dimmed to 0", and a color changed
    /// elsewhere is no longer temporary.
    func roomsChangedFromStream(_ ids: Set<String>) {
        scheduleWidgetRefresh()
        let quiet = ids.filter { Date().timeIntervalSince(lastLocalChange[$0] ?? .distantPast) > 3 }
        let lit = quiet.filter { home.room($0)?.isOn == true }
        if !lit.isEmpty { store.zeroDimmed.subtract(lit) }
        checkTemporaryColors(quiet, turnedOnOutside: lit)
    }

    private func scheduleReload(after delay: Duration = .seconds(1)) {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.reload()
        }
    }

    // MARK: Sending

    /// Called by the sender, at most once a second per grouped light.
    private func deliver(_ command: GroupedLightCommand, to groupedLightID: String) async {
        guard let client else { return }
        do {
            try await client.send(command, toGroupedLight: groupedLightID)
        } catch {
            fail(error)
        }
    }
}
