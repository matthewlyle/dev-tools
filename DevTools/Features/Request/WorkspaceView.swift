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

/// The request as a read-only URL: History replays past requests without
/// exposing the path or parameter editors, and selecting an entry runs it,
/// so there is nothing to send here. It can still be saved.
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

            // A compact width saves from the screen's navigation bar.
            if !compact {
                Button {
                    showSave = true
                } label: {
                    Label("Save Request", systemImage: "bookmark")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .disabled(server == nil)
                .help("Save this request (⌘S)")
            }
        }
        .padding(12)
        .savesCurrentRequest(isPresented: $showSave, server: server)
    }
}
