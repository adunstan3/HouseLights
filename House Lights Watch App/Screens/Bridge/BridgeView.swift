import SwiftUI

/// Bridge (pair): IP field, the press-the-button instruction and Pair; then Paired with
/// room and zone counts and Show rooms. Shown on first launch and from Settings › Bridge.
struct BridgeView: View {
    var isFirstLaunch = false
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @State private var pairing: PairingModel?

    var body: some View {
        Screen(title: "Bridge", showsBack: !isFirstLaunch) {
            if let pairing {
                content(pairing)
            }
        }
        .onAppear {
            if pairing == nil {
                pairing = PairingModel(ip: app.store.bridgeIP ?? app.credentials?.ip,
                                       alreadyPaired: app.credentials != nil && !isFirstLaunch)
            }
        }
        .onDisappear { pairing?.cancel() }
    }

    @ViewBuilder
    private func content(_ pairing: PairingModel) -> some View {
        switch pairing.state {
        case .paired:
            PairedPanel(onShowRooms: showRooms, onRepair: { pairing.startOver() }, onLog: { router.push(.log) })
        default:
            PairForm(pairing: pairing, onPair: { pairing.pair(app: app) }, onLog: { router.push(.log) })
        }
    }

    private func showRooms() {
        app.showPairedConfirmation = false
        router.popToRoot()
    }
}

private struct PairForm: View {
    @Bindable var pairing: PairingModel
    let onPair: () -> Void
    let onLog: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("BRIDGE IP ADDRESS")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            // A TextFieldLink opens the watch's text entry; the label is drawn to match the mockup.
            TextFieldLink(prompt: Text("192.168.1.x")) {
                Text(pairing.ip.isEmpty ? "192.168.1.x" : pairing.ip)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(pairing.ip.isEmpty ? Color(white: 0.45) : .white)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
            } onSubmit: { pairing.ip = $0.trimmingCharacters(in: .whitespaces) }
            .buttonStyle(.plain)
            .disabled(pairing.isWaiting)
            .accessibilityLabel("Bridge IP address")
            .accessibilityValue(pairing.ip)
            .accessibilityIdentifier("ipField")
            instruction
            Button(action: pairing.isWaiting ? pairing.cancel : onPair) {
                Text(pairing.isWaiting ? "Cancel" : "Pair")
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("pairButton")
            footer
        }
    }

    private var instruction: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 7).fill(Color(white: 0.9))
                Circle().strokeBorder(Theme.accent, lineWidth: 3).padding(5)
            }
            .frame(width: 26, height: 26)
            Text(instructionText)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(3)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Metrics.cardRadius).fill(Theme.card))
    }

    private var instructionText: String {
        if case .waiting(let left) = pairing.state { return "Press the bridge’s button now… \(left) s left." }
        return "Press the bridge’s button, then tap Pair within 30 s."
    }

    @ViewBuilder private var footer: some View {
        if case .failed(let message) = pairing.state {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
                .onTapGesture(perform: onLog)
        } else {
            Text("Only re-pair after a bridge reset. \(Text("Log ›").foregroundStyle(Theme.accent).bold())")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
                .contentShape(Rectangle())
                .onTapGesture(perform: onLog)
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("logLink")
                .accessibilityAction { onLog() }
        }
    }
}

private struct PairedPanel: View {
    @Environment(AppModel.self) private var app
    let onShowRooms: () -> Void
    let onRepair: () -> Void
    let onLog: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Theme.accent))
                VStack(alignment: .leading, spacing: 0) {
                    Text("Paired")
                        .font(.system(size: 16, weight: .semibold))
                    Text(summary)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: Metrics.cardRadius).fill(Theme.card))
            Button("Show rooms", action: onShowRooms)
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("showRooms")
            Button("Pair again", action: onRepair)
                .buttonStyle(SecondaryButtonStyle())
            HStack {
                Text(app.credentials?.ip ?? "")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                LogLink(action: onLog)
            }
        }
    }

    private var summary: String {
        let rooms = app.home.rooms.filter { $0.kind == .room }.count
        let zones = app.home.rooms.count - rooms
        if app.phase == .loading || app.phase == .starting { return "Loading rooms…" }
        if case .unreachable = app.phase { return "Saved, but the bridge isn't answering" }
        return "\(rooms) room\(rooms == 1 ? "" : "s") and \(zones) zone\(zones == 1 ? "" : "s")"
    }
}

/// Small "Log ›" link to Settings › Bridge › Log.
struct LogLink: View {
    let action: () -> Void

    var body: some View {
        Text("Log ›")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .frame(minWidth: 44, minHeight: 30, alignment: .trailing)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Bridge log")
            .accessibilityIdentifier("logLink")
            .accessibilityAction { action() }
    }
}
