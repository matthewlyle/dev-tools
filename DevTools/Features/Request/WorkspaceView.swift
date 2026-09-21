import SwiftUI

/// The detail column: request bar on top, breadcrumbs, response below.
struct WorkspaceView: View {
    @Environment(ServerStore.self) private var servers

    private var server: ConnectedServer? {
        servers.selected.flatMap { servers.connectedServer(for: $0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            RequestBarView(server: server)
            Divider()
            NavigationBar(server: server)
            Divider()
            ResponseView(server: server)
        }
        .navigationTitle(servers.selected?.resource.name ?? "Request")
        .navigationSubtitle(server.map { "\($0.connection.kind.rawValue) · \($0.baseURL.host() ?? "")" } ?? "")
    }
}
