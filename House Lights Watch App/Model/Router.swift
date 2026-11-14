import Observation
import SwiftUI

enum Route: Hashable {
    case settings
    case bridge
    case log
    case arrange
    case room(String)
    case colorWheel(String)
    case remoteScenes
    case configs
}

/// One navigation path for the whole app, so taps, debug launch arguments and the
/// Bridge-not-reachable screen can all move between screens.
@MainActor @Observable
final class Router {
    var path: [Route] = []

    func push(_ route: Route) { path.append(route) }
    func pop() { if !path.isEmpty { path.removeLast() } }
    func popToRoot() { path.removeAll() }
}
