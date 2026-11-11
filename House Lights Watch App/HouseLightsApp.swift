import SwiftUI

@main
struct HouseLightsApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: AppModel
    private let log: BridgeLog

    init() {
        let log = BridgeLog(fileURL: RuntimeEnvironment.isTesting ? nil : BridgeLog.defaultURL)
        self.log = log
        let store = RuntimeEnvironment.sharedStore
        _model = State(initialValue: AppModel(environment: .current(log: log.sink, store: store), store: store, log: log))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(log)
                .tint(Theme.accent)
                .task { await model.start() }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active: model.becameActive()
            case .background: model.becameInactive()
            default: break
            }
        }
    }
}
