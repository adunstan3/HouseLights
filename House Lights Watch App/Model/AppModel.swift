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
    let environment: BridgeEnvironment
    private(set) var client: (any BridgeClient)?

    private var streamTask: Task<Void, Never>?
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
    }

    /// The user's grid order (room ids), kept here so the grid redraws when Arrange changes it.
    var gridOrder: [String] = [] { didSet { store.gridOrder = gridOrder } }
    /// Rooms showing a temporary color (with the color set). Observed, so the Temporary
    /// color card appears the moment a change makes a room temporary; saved to the App Group.
    var temporaryRooms: [String: LightColor] = [:] { didSet { store.temporaryRooms = temporaryRooms } }
    /// Rooms whose Back to default was tapped while off.
    var pendingDefaults: Set<String> = [] { didSet { store.pendingDefaults = pendingDefaults } }

    /// The grid's tiles: Hue rooms (not zones) in the user's order.
    var rooms: [Room] { GridOrder.apply(gridOrder, to: home.rooms.filter { $0.kind == .room }) }

    var isActive = false

    // MARK: Connecting

    func start() async {
        credentials = environment.loadCredentials()
        guard let credentials else {
            phase = .unpaired
            log.add(.info, "Not paired: showing the Bridge screen")
            return
        }
        client = environment.makeClient(credentials, log.sink)
        await reload()
    }

    /// Reads everything from the bridge again (Try again, launch, structural events).
    func reload() async {
        guard let client else { await start(); return }
        if home.rooms.isEmpty || phase != .ready { phase = .loading }
        do {
            let fresh = try await client.fetchHome()
            home = fresh
            store.lastKnownRooms = fresh.rooms
            phase = .ready
            log.add(.info, "Loaded \(fresh.rooms.filter { $0.kind == .room }.count) rooms, \(fresh.rooms.filter { $0.kind == .zone }.count) zones, \(fresh.lights.count) lights")
            afterReload()
            if isActive { startEventStream() }
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

    /// Called after a successful pairing on the Bridge screen.
    func didPair(_ paired: PairedBridge) async {
        environment.saveCredentials(paired)
        log.add(.info, "Saved key for bridge at \(paired.ip)")
        client = nil
        home = .empty
        await start()
    }

    func forgetBridge() {
        stopEventStream()
        environment.forgetCredentials()
        credentials = nil
        client = nil
        phase = .unpaired
        log.add(.info, "Forgot bridge key")
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
                do {
                    self?.streamConnected = true
                    for try await events in client.events() {
                        guard let self else { return }
                        if !self.streamConnected { self.streamConnected = true; delay = .seconds(1) }
                        self.apply(events)
                    }
                } catch {}
                guard let self, !Task.isCancelled else { return }
                self.streamConnected = false
                self.log.add(.info, "Event stream dropped; reconnecting in \(delay.components.seconds) s")
                try? await Task.sleep(for: delay)
                delay = min(delay * 2, .seconds(30))
            }
        }
    }

    func stopEventStream() {
        streamTask?.cancel()
        streamTask = nil
        streamConnected = false
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

    /// Bookkeeping after live updates from outside the app (ignoring echoes of our own commands
    /// for 3 s): a room switched on elsewhere is no longer "dimmed to 0", and a color changed
    /// elsewhere is no longer temporary.
    func roomsChangedFromStream(_ ids: Set<String>) {
        let quiet = ids.filter { Date().timeIntervalSince(lastLocalChange[$0] ?? .distantPast) > 3 }
        let lit = quiet.filter { home.room($0)?.isOn == true }
        if !lit.isEmpty { store.zeroDimmed.subtract(lit) }
        checkTemporaryColors(quiet, turnedOnOutside: lit)
    }

    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
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
