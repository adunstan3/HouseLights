import Foundation
import Observation

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

    let log: BridgeLog
    let store: SharedStore
    let environment: BridgeEnvironment
    private(set) var client: (any BridgeClient)?

    private var streamTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?
    /// When the app last sent something to each room, so stream echoes aren't mistaken for outside changes.
    var lastLocalChange: [String: Date] = [:]
    @ObservationIgnored lazy var sender = CommandSender { [weak self] id, command in
        await self?.deliver(command, to: id)
    }

    init(environment: BridgeEnvironment, store: SharedStore = SharedStore(), log: BridgeLog) {
        self.environment = environment
        self.store = store
        self.log = log
        let cached = store.lastKnownRooms
        if !cached.isEmpty { home.rooms = cached }
    }

    /// Rooms and zones in the user's order.
    var rooms: [Room] { GridOrder.apply(store.gridOrder, to: home.rooms) }

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
        } catch {
            fail(error)
        }
    }

    /// Hook for later milestones (temporary-color bookkeeping).
    func afterReload() {}

    func fail(_ error: any Error) {
        let bridgeError = error as? BridgeError ?? .unreachable(error.localizedDescription)
        if bridgeError.isUnreachable || bridgeError.needsRepair {
            phase = .unreachable(bridgeError.localizedDescription)
            stopEventStream()
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
        guard phase == .ready else { return }
        Task { await reload() }   // catch up on anything missed while inactive
    }

    func becameInactive() {
        isActive = false
        stopEventStream()
        log.saveNow()
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
                // Don't let an echo of an older value undo a newer one still waiting to be sent.
                if item.type == "grouped_light", let room = home.rooms.first(where: { $0.groupedLightID == item.id }),
                   sender.isPending(room.groupedLightID) { continue }
                changed.formUnion(home.apply(item))
            }
        }
        if !changed.isEmpty {
            store.lastKnownRooms = home.rooms
            roomsChangedFromStream(changed)
        }
    }

    /// Hook for later milestones (dropping temporary labels on outside changes).
    func roomsChangedFromStream(_ ids: Set<String>) {}

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
