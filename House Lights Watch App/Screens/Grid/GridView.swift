import SwiftUI

/// Milestone 2 stand-in for the Rooms grid (milestone 3).
struct GridView: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    var body: some View {
        Screen(title: "House Lights", showsBack: false) {
            VStack(alignment: .leading, spacing: 4) {
                Button("Settings") { router.push(.settings) }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("gear")
                Text(app.rooms.map(\.name).joined(separator: ", "))
                    .font(.footnote)
            }
        }
    }
}
