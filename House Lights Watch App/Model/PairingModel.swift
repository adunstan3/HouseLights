import Foundation
import Observation

/// Drives the Bridge screen: IP entry, the 30-second pairing window, and the result.
@MainActor @Observable
final class PairingModel {
    enum State: Equatable {
        case idle
        case waiting(secondsLeft: Int)
        case paired
        case failed(String)
    }

    var ip: String
    private(set) var state: State
    private var task: Task<Void, Never>?
    private var ticker: Task<Void, Never>?

    init(ip: String?, alreadyPaired: Bool) {
        self.ip = ip ?? ""
        state = alreadyPaired ? .paired : .idle
    }

    var isWaiting: Bool { if case .waiting = state { true } else { false } }

    func startOver() {
        cancel()
        state = .idle
    }

    func pair(app: AppModel) {
        let ip = ip.trimmingCharacters(in: .whitespaces)
        guard Pairing.isValidIP(ip) else {
            state = .failed("Enter the bridge's IP address, like 192.168.1.20.")
            return
        }
        cancel()
        state = .waiting(secondsLeft: 30)
        app.log.add(.info, "Pairing with \(ip)…")
        let client = app.environment.makePairingClient(ip, app.log.sink)
        ticker = Task { [weak self] in
            for left in stride(from: 29, through: 0, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self, self.isWaiting else { return }
                self.state = .waiting(secondsLeft: left)
            }
        }
        task = Task { [weak self] in
            do {
                let outcome = try await Pairing.run(client: client, ip: ip)
                guard let self, !Task.isCancelled else { return }
                self.ticker?.cancel()
                switch outcome {
                case .paired(let bridge):
                    app.showPairedConfirmation = true
                    await app.didPair(bridge)
                    self.state = .paired
                case .timedOut:
                    app.log.add(.error, "Pairing timed out after 30 s (button not pressed)")
                    self.state = .failed("The bridge didn't answer in time. Press its button, then tap Pair within 30 s.")
                }
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.ticker?.cancel()
                self.state = .failed(Self.message(for: error, ip: ip))
            }
        }
    }

    func cancel() {
        task?.cancel()
        ticker?.cancel()
        task = nil
        ticker = nil
        if isWaiting { state = .idle }
    }

    static func message(for error: any Error, ip: String) -> String {
        switch error as? BridgeError {
        case .unreachable?: "No bridge answered at \(ip). Check the address and that the watch is on home Wi-Fi."
        case .some(let e): e.localizedDescription
        case nil: error.localizedDescription
        }
    }
}
