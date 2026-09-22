import SwiftUI

/// The title menu. The server is the scope everything in the window is a view
/// of, so it's chosen from the title — the HIG's document menu beside the
/// title — rather than navigated to from a sidebar. The actions that act on
/// the server list live here too, on both platforms. iPad passes
/// `showSettings`: the title menu is its one always-present in-window menu,
/// and the HIG keeps settings out of toolbars. The Mac has a Settings scene.
struct ServerMenu: View {
    let showInfo: () -> Void
    var showSettings: (() -> Void)?

    @Environment(AccountStore.self) private var account
    @Environment(ServerStore.self) private var servers

    var body: some View {
        @Bindable var servers = servers

        if servers.entries.isEmpty {
            Text(servers.isRefreshing ? "Finding servers…" : servers.errorMessage ?? "No servers")
        } else {
            Picker("Server", selection: $servers.selectedID) {
                ForEach(servers.sortedEntries) { entry in
                    Text(entry.resource.name)
                        .tag(Optional(entry.id))
                }
            }
            .pickerStyle(.inline)
        }

        Divider()

        Button("Server Info…", action: showInfo)
            .disabled(servers.selected == nil)

        Button("Refresh Servers") {
            guard let token = account.token else { return }
            Task { await servers.refresh(token: token) }
        }
        .disabled(account.token == nil || servers.isRefreshing)

        if let showSettings {
            Divider()
            Button("Settings…", action: showSettings)
        }
    }
}
