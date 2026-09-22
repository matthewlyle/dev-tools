import SwiftUI

/// The title menu. The server is the scope everything in the window is a view
/// of, so it's chosen from the title — the HIG's document menu beside the
/// title — rather than navigated to from a sidebar.
struct ServerMenu: View {
    let showInfo: () -> Void

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
    }
}
