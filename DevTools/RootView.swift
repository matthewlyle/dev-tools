import SwiftUI

struct RootView: View {
    @Environment(AccountStore.self) private var account
    @Environment(ServerStore.self) private var servers

    private var signedIn: Bool {
        if case .signedIn = account.state { return true }
        return false
    }

    var body: some View {
        @Bindable var account = account

        Group {
            switch account.state {
            case .restoring:
                ProgressView()
                    .controlSize(.large)
            case .signedOut, .awaitingApproval:
                SignInView()
            case .signedIn:
                MainSplitView()
            }
        }
        .overlay { LightboxOverlay() }
        #if os(macOS)
        .background { WindowSizer(compact: !signedIn) }
        #endif
        .signOutConfirmation(isPresented: $account.isConfirmingSignOut)
        .task { await account.restore() }
        .task(id: account.token) {
            guard let token = account.token else { return }
            await servers.refresh(token: token)
        }
    }
}

#if os(macOS)
/// Opens the window compact for sign-in and discovery, then grows it to full
/// size the first time the main UI appears — and shrinks back if the user
/// signs out. Only acts on the transition, so it never fights a manual resize.
private struct WindowSizer: NSViewRepresentable {
    let compact: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let compactSize = CGSize(width: 640, height: 560)
    static let fullSize = CGSize(width: 1400, height: 860)

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var applied: Bool? }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        apply(view, context.coordinator)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        apply(view, context.coordinator)
    }

    private func apply(_ view: NSView, _ coordinator: Coordinator) {
        guard coordinator.applied != compact else { return }
        let size = compact ? Self.compactSize : Self.fullSize
        let animate = coordinator.applied != nil && !reduceMotion
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            coordinator.applied = compact
            let frame = window.frame
            let origin = NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2)
            window.setFrame(NSRect(origin: origin, size: size), display: true, animate: animate)
        }
    }
}
#endif
