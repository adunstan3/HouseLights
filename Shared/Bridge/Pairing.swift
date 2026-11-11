import Foundation

/// Pairing: after the user presses the bridge's round button, POST /api answers with a key.
/// We ask every 2 s until it does or 30 s pass. Any error other than "button not pressed"
/// (for example no bridge at that IP) stops at once.
nonisolated enum Pairing {
    enum Outcome: Sendable, Equatable {
        case paired(PairedBridge)
        case timedOut
    }

    static func run(client: any BridgeClient, ip: String, interval: Duration = .seconds(2),
                    timeout: Duration = .seconds(30),
                    sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
                    onAttempt: @Sendable (Int) -> Void = { _ in }) async throws -> Outcome {
        var waited: Duration = .zero
        var attempt = 0
        while true {
            attempt += 1
            onAttempt(attempt)
            if case .paired(let bridge) = try await client.pair(ip: ip) { return .paired(bridge) }
            guard waited + interval <= timeout else { return .timedOut }
            try await sleep(interval)
            waited += interval
        }
    }

    /// Accepts dotted IPv4 addresses such as 192.168.1.23.
    static func isValidIP(_ text: String) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { p in
            guard !p.isEmpty, p.count <= 3, let n = Int(p), (0...255).contains(n) else { return false }
            return String(n) == p
        }
    }
}
