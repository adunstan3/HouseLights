import SwiftUI

/// Routes between first launch (Bridge), Bridge not reachable and the Rooms grid, and
/// registers every pushed screen once.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @State private var router = Router()
    @State private var didOpenDebugScreen = false

    var body: some View {
        NavigationStack(path: $router.path) {
            home
                .navigationDestination(for: Route.self, destination: destination)
        }
        .environment(router)
        .onChange(of: app.phase) { _, phase in
            // Bridge not reachable replaces whatever was open (unless the user is fixing the bridge).
            if case .unreachable = phase, !router.path.contains(.bridge) { router.popToRoot() }
        }
        .task(id: app.phase) { openDebugScreen() }
    }

    @ViewBuilder private var home: some View {
        if app.showPairedConfirmation || app.phase == .unpaired {
            BridgeView(isFirstLaunch: true)
        } else if case .unreachable(let reason) = app.phase {
            UnreachableView(reason: reason)
        } else if app.home.rooms.isEmpty && app.phase != .ready {
            ProgressView()
                .toolbar(.hidden, for: .navigationBar)
        } else {
            GridView()
        }
    }

    @ViewBuilder private func destination(_ route: Route) -> some View {
        switch route {
        case .settings: SettingsView()
        case .bridge: BridgeView()
        case .log: BridgeLogView()
        case .arrange: ScreenPlaceholder(title: "Arrange")
        case .room(let id): ScreenPlaceholder(title: app.room(id)?.name ?? "Room")
        case .colorWheel: ScreenPlaceholder(title: "Color")
        }
    }

    /// `-openScreen settings|bridge|log|arrange|room|wheel` and `-openRoom "Name"` (debug only).
    private func openDebugScreen() {
        guard !didOpenDebugScreen, app.phase == .ready, let screen = RuntimeEnvironment.debugValue("openScreen") else { return }
        didOpenDebugScreen = true
        let roomName = RuntimeEnvironment.debugValue("openRoom")
        let roomID = (app.rooms.first { $0.name == roomName } ?? app.rooms.first)?.id ?? ""
        switch screen {
        case "settings": router.path = [.settings]
        case "bridge": router.path = [.settings, .bridge]
        case "log": router.path = [.settings, .bridge, .log]
        case "arrange": router.path = [.settings, .arrange]
        case "room": router.path = [.room(roomID)]
        case "wheel": router.path = [.room(roomID), .colorWheel(roomID)]
        default: break
        }
    }
}

/// Stand-in for screens built in later milestones.
private struct ScreenPlaceholder: View {
    let title: String
    var body: some View { Screen(title: title) { Text("Coming soon").font(.footnote) } }
}
