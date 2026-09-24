import SwiftUI

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
