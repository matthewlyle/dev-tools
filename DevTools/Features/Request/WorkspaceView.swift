import SwiftUI

struct WorkspaceView: View {
    /// Endpoints edit the request; History replays it read-only, starting
    /// from the URL rather than an editable path and parameter form.
    let editable: Bool

    @Environment(ServerStore.self) private var servers
    @Environment(RequestStore.self) private var requests

    private var server: ConnectedServer? {
        servers.selected.flatMap { servers.connectedServer(for: $0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if editable {
                RequestBarView(server: server)
            } else {
                RequestSummaryBar(server: server)
            }
            Divider()
            if requests.response != nil {
                NavigationBar(server: server)
                Divider()
            }
            ResponseView(server: server, editable: editable)
        }
        .platformNavigationSubtitle(server.map { "\($0.connection.kind.rawValue) · \($0.baseURL.host() ?? "")" } ?? "")
    }
}

/// The request as a read-only URL: History replays past requests without
/// exposing the path or parameter editors, and selecting an entry runs it,
/// so there is nothing to send here.
struct RequestSummaryBar: View {
    let server: ConnectedServer?

    @Environment(RequestStore.self) private var requests

    var body: some View {
        HStack(spacing: 8) {
            Text("GET")
                .font(.code(.caption, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.quaternary, in: .rect(cornerRadius: 5))

            Text(requests.previewURL(for: server))
                .font(.code(.body))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
    }
}
