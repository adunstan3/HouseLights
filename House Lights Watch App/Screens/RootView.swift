import SwiftUI

/// The app's first screen. For now a placeholder; milestone 2 adds first-launch
/// routing (Bridge screen when no key is saved) and milestone 3 the Rooms grid.
struct RootView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "lightbulb")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text("House Lights")
                .font(.headline.bold())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}

#Preview {
    RootView()
}
