import SwiftUI

enum SidebarItem: Hashable {
    case server(String)
    case endpoints
    case history
    case activity
}

struct MainSplitView: View {
    @Environment(ServerStore.self) private var servers
    @State private var sidebar: SidebarItem?

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $sidebar)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } content: {
            Group {
                switch sidebar {
                case .server(let id):
                    if let entry = servers.entry(id: id) {
                        ServerDetailView(entry: entry)
                            .id(id)
                    } else {
                        ContentUnavailableView("Server Not Found", systemImage: "server.rack")
                    }
                case .endpoints:
                    EndpointCatalogView()
                case .history:
                    HistoryListView()
                case .activity:
                    ActivityControlsView()
                case nil:
                    ContentUnavailableView(
                        "Nothing Selected",
                        systemImage: "sidebar.left",
                        description: Text("Pick a server or a Library item in the sidebar.")
                    )
                }
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 480)
        } detail: {
            if sidebar == .activity {
                ActivityEventsView()
            } else {
                WorkspaceView()
            }
        }
        .onAppear {
            if sidebar == nil, let id = servers.selectedID {
                sidebar = .server(id)
            }
        }
    }
}

/// Standalone activity window so the feed can sit beside the main window.
struct ActivityWindowView: View {
    var body: some View {
        NavigationSplitView {
            ActivityControlsView(showsOpenWindow: false)
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 400)
        } detail: {
            ActivityEventsView()
        }
    }
}
