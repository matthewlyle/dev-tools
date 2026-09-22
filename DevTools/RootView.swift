import SwiftUI

struct RootView: View {
    @Environment(AccountStore.self) private var account
    @Environment(ServerStore.self) private var servers

    /// Once a server has connected this session the split view stays; later
    /// server switches show their own probing state in place.
    @State private var hasConnected = false

    private var connected: ConnectedServer? {
        servers.selected.flatMap { servers.connectedServer(for: $0) }
    }

    /// Discovery or probing is still in flight for some known server. Once
    /// every server has answered — even all unreachable — the real UI shows
    /// so the user can act on it.
    private var stillConnecting: Bool {
        servers.isRefreshing || servers.entries.contains { $0.isProbing || $0.probes.isEmpty }
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
                if !hasConnected, stillConnecting {
                    ConnectingView(
                        serverName: servers.selected?.resource.name,
                        findingServers: servers.isRefreshing
                    )
                } else {
                    MainSplitView()
                }
            }
        }
        .overlay { LightboxOverlay() }
        .signOutConfirmation(isPresented: $account.isConfirmingSignOut)
        .task { await account.restore() }
        .task(id: account.token) {
            guard let token = account.token else { return }
            await servers.refresh(token: token)
        }
        .onChange(of: connected?.machineID, initial: true) { _, id in
            if id != nil { hasConnected = true }
        }
    }
}

/// Full-window splash shown while servers are being discovered and probed,
/// in place of a dimmed, empty three-column layout.
private struct ConnectingView: View {
    let serverName: String?
    let findingServers: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var sentence: String {
        if findingServers { return "Finding your servers" }
        if let serverName { return "Connecting to \(serverName)" }
        return "Connecting to your servers"
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "server.rack")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(sentence)
                .font(.title3)
                .contentTransition(.interpolate)
                .animation(reduceMotion ? nil : .snappy, value: sentence)
            ProgressView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
