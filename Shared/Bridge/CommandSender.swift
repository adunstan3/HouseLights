import Foundation

/// Sends at most one command per grouped light per interval (the bridge handles about one
/// grouped_light command per second). Commands queued in between merge, so only the
/// latest value goes out; stale ones are dropped.
@MainActor
final class CommandSender {
    typealias Send = @MainActor (String, GroupedLightCommand) async -> Void

    private let interval: Duration
    private let send: Send
    private let clock = ContinuousClock()
    private var pending: [String: GroupedLightCommand] = [:]
    private var lastSent: [String: ContinuousClock.Instant] = [:]
    private var scheduled: Set<String> = []

    init(interval: Duration = .seconds(1), send: @escaping Send) {
        self.interval = interval
        self.send = send
    }

    func enqueue(_ command: GroupedLightCommand, to id: String) {
        pending[id] = pending[id].map { $0.merged(with: command) } ?? command
        guard !scheduled.contains(id) else { return }
        scheduled.insert(id)
        let wait = lastSent[id].map { ($0 + interval) - clock.now } ?? .zero
        Task {
            if wait > .zero { try? await Task.sleep(for: wait) }
            await flush(id)
        }
    }

    /// Whether a command for this id is waiting to go out.
    func isPending(_ id: String) -> Bool { pending[id] != nil }

    private func flush(_ id: String) async {
        scheduled.remove(id)
        guard let command = pending.removeValue(forKey: id) else { return }
        lastSent[id] = clock.now
        await send(id, command)
    }
}
