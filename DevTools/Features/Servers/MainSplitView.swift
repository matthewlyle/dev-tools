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
    @Environment(AccountStore.self) private var account
    @Environment(ServerStore.self) private var servers
    @Environment(RequestStore.self) private var requests
    @AppStorage("serverSection") private var section: ServerSection = .endpoints
    #if !os(macOS)
    @State private var showSettings = false
    @AppStorage("sectionListVisible") private var sectionListVisible = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                .modifier(Header(title: title, entry: servers.selected, section: $section))
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
                        if sectionListVisible {
                            sectionList
                                .containerRelativeFrame(.horizontal) { length, _ in min(max(length * 0.4, 320), 460) }
                                .transition(reduceMotion ? .opacity : .move(edge: .leading))
                            Divider()
                        }
                        detailPane
                    }
                    .animation(.smooth, value: sectionListVisible)
                } else {
                    sectionList
                }
            }
            .modifier(Header(title: title, entry: servers.selected, section: $section))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarRole(.editor)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        sectionListVisible.toggle()
                    } label: {
                        Label(sectionListVisible ? "Hide Section List" : "Show Section List", systemImage: "sidebar.leading")
                    }
                    .keyboardShortcut("s", modifiers: [.command, .control])
                    .disabled(servers.selected == nil)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Refresh Servers") {
                            guard let token = account.token else { return }
                            Task { await servers.refresh(token: token) }
                        }
                        .keyboardShortcut("r", modifiers: .command)
                        .disabled(account.token == nil || servers.isRefreshing)
                        Button("Connect") {
                            guard let id = servers.selectedID else { return }
                            Task { await servers.probe(id: id) }
                        }
                        .disabled(servers.selected == nil || servers.selected?.isProbing == true)
                        Divider()
                        Button("Settings…") { showSettings = true }
                            .keyboardShortcut(",", modifiers: .command)
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }
    #endif

    /// Title leading (the server, with its menu), section switcher centre.
    /// Server Info… is a menu item, so its popover drops from the title area.
    private struct Header: ViewModifier {
        let title: String
        let entry: ServerStore.Entry?
        @Binding var section: ServerSection
        @State private var showInfo = false

        func body(content: Content) -> some View {
            content
                .navigationTitle(title)
                .toolbarTitleMenu { ServerMenu(showInfo: { showInfo = true }) }
                .toolbar {
                    ToolbarItem(placement: .secondaryAction) {
                        SectionPicker(section: $section)
                            .fixedSize()
                    }
                }
                .popover(
                    isPresented: $showInfo,
                    attachmentAnchor: .rect(.rect(CGRect(x: 48, y: 0, width: 1, height: 1))),
                    arrowEdge: .top
                ) {
                    if let entry { ServerInfoView(entry: entry) }
                }
                .focusedSceneValue(\.showServerInfo, entry == nil ? nil : ShowServerInfoAction { showInfo = true })
        }
    }

    @ViewBuilder
    private var sectionList: some View {
        if let entry = servers.selected {
            Group {
                switch section {
                case .endpoints:
                    EndpointListView(server: connected, serverID: entry.id)
                case .history:
                    HistoryListView(serverID: entry.id)
                case .activity:
                    ActivityControlsView()
                case .mediaQuery:
                    MediaQueryBuilderView(server: connected)
                }
            }
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
