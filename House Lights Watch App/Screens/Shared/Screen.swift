import SwiftUI

/// A full-screen page with its title on the clock's line ("‹ Settings"). The system
/// navigation bar is hidden because watchOS 26's round back button covers content.
struct Screen<Content: View>: View {
    let title: String
    var showsBack = true
    /// Back goes straight to the grid (Settings and its pages) rather than one screen back.
    var backToGrid = false
    @ViewBuilder var content: () -> Content
    @Environment(Router.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.headerGap) {
            ScreenHeader(title: title, showsBack: showsBack) { backToGrid ? router.popToRoot() : router.pop() }
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, Metrics.sideMargin)
        .padding(.top, Metrics.headerTop)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.background)
        .ignoresSafeArea(edges: [.top, .bottom])
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct ScreenHeader: View {
    let title: String
    var showsBack = true
    var back: () -> Void = {}

    var body: some View {
        HStack(spacing: 4) {
            if showsBack {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }
            Text(title)
                .font(Theme.titleFont)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(height: Metrics.headerHeight)
        .padding(.trailing, Metrics.clockClearance)
        .contentShape(Rectangle())
        .onTapGesture { if showsBack { back() } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(showsBack ? "Back from \(title)" : title)
        .accessibilityAddTraits(showsBack ? .isButton : .isHeader)
        .accessibilityIdentifier(showsBack ? "back" : "title")
        .accessibilityAction { if showsBack { back() } }
    }
}

/// Shared measurements, in points, from the mockups (drawn at 2× the 49mm screen).
enum Metrics {
    static let sideMargin: CGFloat = 10
    /// Puts the header's text on the same line as the clock.
    static let headerTop: CGFloat = 15
    static let headerHeight: CGFloat = 26
    static let headerGap: CGFloat = 6
    /// Room left on the right of the header for the clock.
    static let clockClearance: CGFloat = 56
    static let cardRadius: CGFloat = 14
    static let buttonHeight: CGFloat = 34
}
