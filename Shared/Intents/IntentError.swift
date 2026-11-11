import Foundation

/// What Siri says when something goes wrong — plainly.
nonisolated enum IntentError: Error, CustomLocalizedStringResourceConvertible, Equatable {
    case unreachable
    case notPaired
    case needsRepair
    case roomGone

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .unreachable: "I can’t reach your Hue Bridge. House Lights only works on your home Wi-Fi."
        case .notPaired: "House Lights isn’t paired with your Hue Bridge yet. Open the app to pair it."
        case .needsRepair: "Your Hue Bridge needs to be paired again. Open House Lights, then Settings, then Bridge."
        case .roomGone: "That room isn’t on your Hue Bridge any more."
        }
    }

    static func from(_ error: any Error) -> IntentError {
        if let e = error as? IntentError { return e }
        if let e = error as? BridgeError, e.needsRepair { return .needsRepair }
        if let e = error as? BridgeError, e == .notPaired { return .notPaired }
        return .unreachable
    }
}
