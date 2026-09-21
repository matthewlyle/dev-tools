import SwiftUI

/// What you're doing with the selected server. The server is the context;
/// these are views onto it, never peers of it.
enum ServerSection: String, CaseIterable, Identifiable {
    case endpoints = "Endpoints"
    case history = "History"
    case activity = "Activity"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .endpoints: "book.closed"
        case .history: "clock"
        case .activity: "dot.radiowaves.left.and.right"
        }
    }
}

struct MainSplitView: View {
    @Environment(ServerStore.self) private var servers
    @AppStorage("serverSection") private var section: ServerSection = .endpoints

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
            if section == .activity {
                ActivityEventsView()
            } else {
                WorkspaceView()
            }
        }
    }
}

/// Standalone activity window so the feed can sit beside the main window.
/// It follows the main window's selected server.
struct ActivityWindowView: View {
    var body: some View {
        NavigationSplitView {
            ActivityControlsView(showsOpenWindow: false)
                .navigationTitle("Activity")
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 400)
        } detail: {
            ActivityEventsView()
        }
    }
}
