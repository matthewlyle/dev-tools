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

struct SectionPicker: View {
    @Binding var section: ServerSection

    var body: some View {
        Picker("Section", selection: $section) {
            ForEach(ServerSection.allCases) { section in
                Text(section.rawValue).tag(section)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

/// One header over the whole window: the server as the title (and its menu,
/// which switches it), the section switcher in the centre, the section's
/// filters trailing. The section list and its detail sit beneath.
struct MainSplitView: View {
    @Environment(ServerStore.self) private var servers
    @Environment(RequestStore.self) private var requests
    @AppStorage("serverSection") private var section: ServerSection = .endpoints
    #if !os(macOS)
    @State private var showSettings = false
    #endif

    private var connected: ConnectedServer? {
        servers.selected.flatMap { servers.connectedServer(for: $0) }
    }

    private var title: String { servers.selected?.resource.name ?? "Servers" }

    var body: some View {
        split
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

    #if os(macOS)
    private var split: some View {
        NavigationSplitView {
            sectionList
                .navigationSplitViewColumnWidth(min: 340, ideal: 440, max: 600)
        } detail: {
            detailPane
                .modifier(Header(title: title, section: $section))
        }
    }
    #else
    /// iPad has no window-wide toolbar over split columns, so the list and
    /// detail are two panes under one navigation bar. The `.editor` role is
    /// what keeps the title leading with `.secondaryAction` in the centre,
    /// matching the Mac toolbar.
    private var split: some View {
        NavigationStack {
            Group {
                if servers.selected != nil {
                    HStack(spacing: 0) {
                        sectionList
                            .containerRelativeFrame(.horizontal) { length, _ in min(max(length * 0.4, 320), 460) }
                        Divider()
                        detailPane
                    }
                } else {
                    sectionList
                }
            }
            .modifier(Header(title: title, section: $section))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarRole(.editor)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .keyboardShortcut(",", modifiers: .command)
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }
    #endif

    /// Title leading (the server, with its menu), section switcher centre.
    private struct Header: ViewModifier {
        let title: String
        @Binding var section: ServerSection

        func body(content: Content) -> some View {
            content
                .navigationTitle(title)
                .toolbarTitleMenu { ServerMenu() }
                .toolbar {
                    ToolbarItem(placement: .secondaryAction) {
                        SectionPicker(section: $section)
                            .fixedSize()
                    }
                }
        }
    }

    @ViewBuilder
    private var sectionList: some View {
        if let entry = servers.selected {
            ServerDetailView(entry: entry, section: $section)
                .id(entry.id)
        } else {
            ContentUnavailableView(
                "No Server Selected",
                systemImage: "server.rack",
                description: Text("Choose a server from the title menu.")
            )
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        switch section {
        case .activity:
            ActivityEventsView()
        case .mediaQuery:
            MediaResultsView(server: connected)
        case .endpoints, .history:
            WorkspaceView(editable: section == .endpoints)
        }
    }
}
