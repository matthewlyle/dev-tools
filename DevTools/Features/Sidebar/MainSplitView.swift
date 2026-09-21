import SwiftUI

enum ServerSection: String, CaseIterable, Identifiable {
    case endpoints = "Endpoints"
    case history = "History"
    case activity = "Activity"
    case mediaQuery = "Media"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .endpoints: "book.closed"
        case .history: "clock"
        case .activity: "dot.radiowaves.left.and.right"
        case .mediaQuery: "line.3.horizontal.decrease.circle"
        }
    }
}

struct MainSplitView: View {
    @Environment(ServerStore.self) private var servers
    @Environment(RequestStore.self) private var requests
    @AppStorage("serverSection") private var section: ServerSection = .endpoints

    private var connected: ConnectedServer? {
        servers.selected.flatMap { servers.connectedServer(for: $0) }
    }

    var body: some View {
        @Bindable var servers = servers

        NavigationSplitView {
            SidebarView(selection: $servers.selectedID)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } content: {
            Group {
                if let entry = servers.selected {
                    ServerDetailView(entry: entry, section: $section)
                        .id(entry.id)
                } else {
                    ContentUnavailableView(
                        "No Server Selected",
                        systemImage: "server.rack",
                        description: Text("Pick a server in the sidebar.")
                    )
                }
            }
            .navigationSplitViewColumnWidth(min: 340, ideal: 440, max: 600)
        } detail: {
            switch section {
            case .activity:
                ActivityEventsView()
            case .mediaQuery:
                MediaResultsView(server: connected)
            case .endpoints, .history:
                WorkspaceView(editable: section == .endpoints)
            }
        }
        .task(id: connected?.machineID) {
            if let connected { await requests.preloadOptions(on: connected) }
        }
        .onChange(of: section) { _, _ in
            requests.reset()
        }
        .onChange(of: servers.selectedID) { _, _ in
            requests.reset()
        }
    }
}
