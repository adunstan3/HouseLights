import Foundation

nonisolated enum BridgeError: Error, Sendable, Equatable, LocalizedError {
    /// No answer: not on home Wi-Fi, bridge unplugged, wrong IP.
    case unreachable(String)
    /// The bridge presented a different certificate than the one seen at pairing.
    case certificateChanged
    /// The key was rejected (bridge reset, or the app was removed in the Hue app).
    case unauthorized
    /// Too many requests (HTTP 429). The sender's throttle should prevent this.
    case rateLimited
    case http(Int, String)
    case badResponse(String)
    case notPaired

    var errorDescription: String? {
        switch self {
        case .unreachable(let why): "Bridge not reachable (\(why))"
        case .certificateChanged: "The bridge's certificate changed. Re-pair in Settings › Bridge."
        case .unauthorized: "The bridge didn't accept the key. Re-pair in Settings › Bridge."
        case .rateLimited: "The bridge is busy (too many requests)."
        case .http(let code, let msg): "Bridge error \(code)\(msg.isEmpty ? "" : ": \(msg)")"
        case .badResponse(let why): "Unexpected reply from the bridge (\(why))"
        case .notPaired: "Not paired with a bridge."
        }
    }

    /// Errors that mean "show Bridge not reachable" rather than a one-off failure.
    var isUnreachable: Bool {
        if case .unreachable = self { return true }
        return false
    }

    var needsRepair: Bool { self == .certificateChanged || self == .unauthorized }
}
