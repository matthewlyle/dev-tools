import SwiftUI

/// The title menu. The server is the scope everything in the window is a view
/// of, so it's chosen from the title — the HIG's document menu beside the
/// title — rather than navigated to from a sidebar.
struct ServerMenu: View {
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

        Button("Refresh Servers") {
            guard let token = account.token else { return }
            Task { await servers.refresh(token: token) }
        }
        .disabled(account.token == nil || servers.isRefreshing)
    }
}
