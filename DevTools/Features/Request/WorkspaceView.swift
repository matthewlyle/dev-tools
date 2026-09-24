import SwiftUI

struct WorkspaceView: View {
    let editable: Bool

    @Environment(ServerStore.self) private var servers
    @Environment(RequestStore.self) private var requests

    private var server: ConnectedServer? {
        servers.selected.flatMap { servers.connectedServer(for: $0) }
    }

    var body: some View {
        ResponseView(server: server, editable: editable) {
            if editable {
                RequestBarView(server: server)
            } else {
                RequestSummaryBar(server: server)
            }
        }
        .requestScreenActions(server: server)
    }
}

struct RequestSummaryBar: View {
    let server: ConnectedServer?

    @Environment(RequestStore.self) private var requests
    @Environment(\.isCompactWidth) private var compact
    @State private var showSave = false

    var body: some View {
        HStack(spacing: 8) {
            if requests.recordsNavigation {
                HistoryNavButtons(server: server)
            }
            Text("GET")
                .font(.code(.caption, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.quaternary, in: .rect(cornerRadius: 5))

            Text(requests.previewURL(for: server))
                .font(.code(.body))
                .lineLimit(compact ? 3 : 1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .savesCurrentRequest(isPresented: $showSave, server: server)
    }
}
