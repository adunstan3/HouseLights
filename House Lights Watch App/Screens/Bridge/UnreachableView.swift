import SwiftUI

/// Bridge not reachable (mockups/4-bridge-not-reachable.png): shown whenever the bridge
/// doesn't answer. Try again reloads; Bridge settings opens the Bridge screen.
struct UnreachableView: View {
    let reason: String
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @State private var retrying = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 46, height: 46)
                .background(Circle().fill(Theme.secondaryButton))
            Text("Can’t reach your bridge")
                .font(.system(size: 17, weight: .bold))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
            Button(retrying ? "Trying…" : "Try again") {
                retrying = true
                Task {
                    await app.reload()
                    retrying = false
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(retrying)
            .accessibilityIdentifier("tryAgain")
            Button("Bridge settings") { router.push(.bridge) }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("bridgeSettings")
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
    }

    /// The mockup's wording for "no answer"; the specific reason when re-pairing is needed.
    private var message: String {
        if reason.contains("Re-pair") { return reason }
        return "Lights only work on your home Wi-Fi. Join it, or check that the bridge is plugged in."
    }
}
