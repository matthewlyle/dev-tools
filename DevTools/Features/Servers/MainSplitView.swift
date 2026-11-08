import OSLog
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

extension EnvironmentValues {
    /// On macOS a collapsed column's view stays alive, so toolbar items over
    /// the list gate on this or they'd outlive it.
    @Entry var sectionListVisible = true
    @Entry var sectionIsActive = true
    @Entry var showSectionDetail: ShowSectionDetailAction? = nil
    @Entry var posterZoom: Namespace.ID? = nil
    @Entry var connectionInTabBar = false
}

struct ShowSectionDetailAction {
    let run: () -> Void

    func callAsFunction() { run() }
}

private struct ListFilter<Actions: View>: ViewModifier {
    @Binding var text: String
    let prompt: String
    let actions: Actions?

    @Environment(\.isCompactWidth) private var compact

    private var actionsBesideField: Bool {
        #if os(iOS)
        !compact
        #else
        false
        #endif
    }

    func body(content: Content) -> some View {
        if compact {
            content
                .searchable(text: $text, prompt: Text(prompt))
                .modifier(ActionsInBar(actions: actions))
        } else if actionsBesideField {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    field
                    if let actions {
                        actions
                            .labelStyle(.iconOnly)
                            .imageScale(.large)
                    }
                }
                .modifier(FieldPadding())
                content
            }
        } else {
            VStack(spacing: 0) {
                field.modifier(FieldPadding())
                content
            }
            .modifier(ActionsInBar(actions: actions))
        }
    }

    private var field: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Label("Clear Filter", systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.quaternary, in: .rect(cornerRadius: 8))
    }
}

private struct FieldPadding: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }
}

private struct ActionsInBar<Actions: View>: ViewModifier {
    let actions: Actions?

    /// A list without actions adds no toolbar at all, rather than one whose
    /// content changes as its section shows and hides.
    @ViewBuilder
    func body(content: Content) -> some View {
        if let actions {
            content.sectionListToolbar {
                ToolbarItemGroup(placement: .primaryAction) { actions }
            }
        } else {
            content
        }
    }
}

extension View {
    func listFilter<Actions: View>(text: Binding<String>, prompt: String, @ViewBuilder actions: () -> Actions) -> some View {
        modifier(ListFilter(text: text, prompt: prompt, actions: actions()))
    }

    func listFilter(text: Binding<String>, prompt: String) -> some View {
        modifier(ListFilter<EmptyView>(text: text, prompt: prompt, actions: nil))
    }
}

private struct SectionListToolbar<Items: ToolbarContent>: ViewModifier {
    @Environment(\.sectionListVisible) private var visible
    @Environment(\.sectionIsActive) private var active
    let followsList: Bool
    let items: Items

    /// Branch inside `.toolbar`, not around it: branching around it gives the
    /// view a new identity on every switch. Not `ToolbarContent.hidden`: on macOS
    /// a hidden item still holds its slot, pushing the sidebar button away.
    func body(content: Content) -> some View {
        let shown = active && (visible || !followsList)
        content.toolbar {
            if shown { items }
        }
    }
}

private struct SectionResident: ViewModifier {
    let active: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        // The outgoing section leaves at once: fading, it shows unblurred through
        // the toolbar's edge effect. Only opacity animates, since the section flag
        // reaches toolbar items and focused values, which must swap in one frame.
        content
            .animation(active && !reduceMotion ? .smooth(duration: 0.12) : nil) {
                $0.opacity(active ? 1 : 0)
            }
            .keyframeAnimator(initialValue: CGFloat.zero, trigger: active) { view, y in
                view.offset(y: y)
            } keyframes: { _ in
                KeyframeTrack {
                    MoveKeyframe(active && !reduceMotion ? 6 : 0)
                    SpringKeyframe(0, duration: 0.3, spring: .snappy)
                }
            }
            .allowsHitTesting(active)
            .disabled(!active) // Hit testing alone leaves its controls reachable by keyboard focus.
            .accessibilityHidden(!active)
            .environment(\.sectionIsActive, active)
    }
}

extension View {
    func sectionResident(active: Bool) -> some View {
        modifier(SectionResident(active: active))
    }
}

extension View {
    func sectionListToolbar<Items: ToolbarContent>(followsList: Bool = true, @ToolbarContentBuilder items: () -> Items) -> some View {
        modifier(SectionListToolbar(followsList: followsList, items: items()))
    }
}

/// On iOS a Media item opens in a sheet wherever the detail is compact or
/// taller than wide: an inspector there squeezes the poster grid and can't zoom.
private struct SectionInspector: ViewModifier {
    let section: ServerSection
    let server: ConnectedServer?

    @Environment(ActivityStore.self) private var activity
    @Environment(MediaQueryStore.self) private var mediaQuery
    @Environment(RequestStore.self) private var requests
    @Environment(\.sectionIsActive) private var isActive
    @Environment(\.isCompactWidth) private var compact
    @State private var tall = false
    @Namespace private var posterZoom
    @State private var eventDetent: PresentationDetent = .medium

    private enum Shown {
        case event(NotificationEvent)
        case item(MediaItem)
    }

    // Read here, not in the binding or content closures, so Observation tracks exactly what's presented.
    private var shown: Shown? {
        guard isActive else { return nil }
        switch section {
        case .activity:
            return activity.selectedEvent.map(Shown.event)
        case .mediaQuery:
            guard mediaQuery.showsItemInfo, let id = mediaQuery.selectedItemID,
                  let node = requests.document?.tree?.children.first(where: { $0.id == id })
            else { return nil }
            return .item(MediaItem(node: node))
        case .endpoints, .history:
            return nil
        }
    }

    private var itemInSheet: Bool {
        #if os(iOS)
        compact || tall
        #else
        false
        #endif
    }

    /// An adapted inspector opens full height on an iPhone whatever its
    /// detents say; a real sheet honours them.
    private var eventInSheet: Bool {
        #if os(iOS)
        compact
        #else
        false
        #endif
    }

    func body(content: Content) -> some View {
        let shown = shown
        let isActive = isActive
        let itemInSheet = itemInSheet
        let eventInSheet = eventInSheet
        let sheetItem: MediaItem? = if itemInSheet, case .item(let item) = shown { item } else { nil }
        let sheetEvent: NotificationEvent? = if eventInSheet, case .event(let event) = shown { event } else { nil }
        let inspected = sheetItem == nil && sheetEvent == nil ? shown : nil
        content
            #if os(iOS)
            // UIKit hosts an inspector's main content in its own opaque
            // container, which covers a well drawn behind the modifier.
            .wellBackground()
            .environment(\.posterZoom, posterZoom)
            #endif
            .inspector(isPresented: Binding(get: { inspected != nil }, set: { if !$0, isActive, sheetItem == nil, sheetEvent == nil { dismiss() } })) {
                switch inspected {
                case .event(let event):
                    EventInspector(event: event)
                        .inspectorColumnWidth(min: 320, ideal: 460, max: 800)
                case .item(let item):
                    mediaInfo(item)
                        .inspectorColumnWidth(min: 280, ideal: 340, max: 480)
                case nil:
                    EmptyView()
                }
            }
            #if os(iOS)
            // The window's lightbox draws under a sheet, so the sheet needs its own.
            .sheet(isPresented: Binding(get: { sheetItem != nil }, set: { if !$0, isActive, itemInSheet { dismiss() } })) {
                if let sheetItem {
                    mediaInfo(sheetItem, showsPoster: true)
                        .overlay { LightboxOverlay() }
                        .navigationTransition(.zoom(sourceID: sheetItem.id, in: posterZoom))
                }
            }
            .sheet(isPresented: Binding(get: { sheetEvent != nil }, set: { if !$0, isActive, eventInSheet { dismiss() } })) {
                if let sheetEvent {
                    EventInspector(event: sheetEvent)
                        .presentationDetents([.medium, .large], selection: $eventDetent)
                        .presentationDragIndicator(.visible)
                        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                }
            }
            .onGeometryChange(for: Bool.self) { $0.size.height > $0.size.width } action: { tall = $0 }
            #endif
            .onChange(of: inspected == nil && sheetEvent == nil) { _, closed in
                if closed { eventDetent = .medium }
            }
    }

    private func mediaInfo(_ item: MediaItem, showsPoster: Bool = false) -> some View {
        MediaInfoView(item: item, server: server, showsPoster: showsPoster) { mediaQuery.showsItemInfo = false }
    }

    private func dismiss() {
        switch section {
        case .activity: activity.selectedEventID = nil
        case .mediaQuery: mediaQuery.showsItemInfo = false
        case .endpoints, .history: break
        }
    }
}

extension View {
    func sectionListStyle() -> some View {
        listStyle(.inset)
            .scrollContentBackground(.hidden)
    }

    /// iOS gives inset rows an opaque cell background that covers the well.
    @ViewBuilder
    func sectionListRow(selected: Bool = false) -> some View {
        #if os(iOS)
        listRowBackground(
            RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Color.accentColor.opacity(0.22) : .clear)
                .padding(.horizontal, 8)
        )
        #else
        self
        #endif
    }

    func sectionListButtonRow(selected: Bool) -> some View {
        listRowBackground(
            RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Color.accentColor.opacity(0.22) : .clear)
                .padding(.horizontal, 8)
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

enum ListSignpost {
    static let signposter = OSSignposter(subsystem: "mldgg.devtools", category: "lists")
}

extension View {
    func sectionListRows() -> some View {
        listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    func sectionColumnList() -> some View {
        listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .onAppear { ListSignpost.signposter.emitEvent("List mounted") }
    }
}

struct SectionColumnHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .listRowInsets(EdgeInsets())
    }
}

extension View {
    func sectionColumnRow(selected: Bool = false) -> some View {
        padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(selected ? Color.accentColor.opacity(0.22) : .clear, in: .rect(cornerRadius: 6))
            .padding(.horizontal, 6)
    }
}

struct SectionPicker: View {
    @Binding var section: ServerSection

    var body: some View {
        // A segmented control renders unusably in the toolbar overflow menu, so
        // a narrow window gets a pop-up.
        ViewThatFits(in: .horizontal) {
            segmented
            menu
        }
    }

    private var segmented: some View {
        Picker("Section", selection: $section) {
            ForEach(ServerSection.allCases) { section in
                Text(section.rawValue).tag(section)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    private var menu: some View {
        Picker("Section", selection: $section) {
            ForEach(ServerSection.allCases) { section in
                Label(section.rawValue, systemImage: section.systemImage).tag(section)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
    }
}

struct MainSplitView: View {
    @Environment(AccountStore.self) private var account
    @Environment(ServerStore.self) private var servers
    @Environment(RequestStore.self) private var requests
    @Environment(ActivityStore.self) private var activity
    @AppStorage("serverSection") private var section: ServerSection = .endpoints
    @State private var hasConnected = false
    #if os(macOS)
    @State private var columns: NavigationSplitViewVisibility = .all
    #else
    @AppStorage("sectionListVisible") private var sectionListVisible = true
    @Environment(\.isCompactWidth) private var compact
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var pushed: Set<ServerSection> = []
    #endif

    private var connected: ConnectedServer? {
        servers.selected.flatMap { servers.connectedServer(for: $0) }
    }

    private var stillConnecting: Bool {
        servers.isRefreshing || servers.entries.contains { $0.isProbing || $0.probes.isEmpty }
    }

    private var isInitialLoad: Bool { !hasConnected && connected == nil }

    private var title: String {
        if isInitialLoad, servers.isRefreshing { return "" }
        return servers.selected?.resource.name ?? "Servers"
    }

    /// Swaps the workspace before the incoming section builds, not reactively
    /// after: otherwise its detail builds a text view for the outgoing response
    /// only to tear it down, stalling the switch.
    private var sectionBinding: Binding<ServerSection> {
        Binding(
            get: { section },
            set: { newValue in
                guard newValue != section else { return }
                let state = ListSignpost.signposter.beginInterval("Section switch")
                requests.switchWorkspace(from: section.rawValue, to: newValue.rawValue)
                withoutToolbarFade { section = newValue }
                ListSignpost.signposter.endInterval("Section switch", state)
            }
        )
    }

    var body: some View {
        split
            .task(id: connected?.machineID) {
                if let connected { await requests.preloadOptions(on: connected) }
            }
            .onChange(of: servers.selectedID) { _, id in
                requests.resetAllWorkspaces()
                if let listening = activity.server, listening.machineID != id {
                    activity.disconnect()
                    activity.clear()
                }
                #if os(iOS)
                pushed.removeAll()
                #endif
            }
            .onChange(of: connected?.machineID, initial: true) { _, id in
                if id != nil { hasConnected = true }
            }
            .onChange(of: connected) { _, connected in
                guard let connected, let listening = activity.server, activity.status.isActive,
                      listening.machineID == connected.machineID, connected != listening
                else { return }
                activity.connect(to: connected)
            }
            .onChange(of: section, initial: true) { _, section in
                requests.recordsNavigation = section != .mediaQuery
            }
            #if os(iOS)
            .onChange(of: requests.pathFocusPending) { _, pending in
                guard pending, compact, servers.selected != nil else { return }
                if section != .endpoints {
                    sectionBinding.wrappedValue = .endpoints
                    requests.requestPathFocus()
                }
                pushed.insert(.endpoints)
            }
            #endif
    }

    #if os(macOS)
    @ViewBuilder
    private var split: some View {
        if isInitialLoad {
            loadingShell
        } else {
            NavigationSplitView(columnVisibility: $columns) {
                sectionList
                    .navigationSplitViewColumnWidth(min: 260, ideal: 340, max: 800)
                    .environment(\.sectionListVisible, columns != .detailOnly)
            } detail: {
                detailPane
                    .modifier(Header(title: title, entry: servers.selected, section: sectionBinding))
            }
        }
    }
    #else
    @ViewBuilder
    private var split: some View {
        if isInitialLoad {
            NavigationStack { loadingShell }
        } else if compact {
            compactSplit
        } else {
            regularSplit
        }
    }
    #endif

    private var loadingShell: some View {
        connectionStatus
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .wellBackground()
            .modifier(Header(title: title, entry: servers.selected, section: nil))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
    }

    #if os(iOS)

    private var regularSplit: some View {
        NavigationStack {
            Group {
                if servers.selected != nil {
                    ListDetailPanes(showsList: sectionListVisible && !listPaneEmpty) {
                        sectionList
                    } detail: {
                        detailPane
                    }
                } else {
                    sectionList
                }
            }
            .modifier(Header(title: title, entry: servers.selected, section: sectionBinding))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarRole(.editor)
            .toolbar {
                ToolbarItem(id: "window.sectionList", placement: .topBarLeading) {
                    Button {
                        sectionListVisible.toggle()
                    } label: {
                        Label(sectionListVisible ? "Hide Section List" : "Show Section List", systemImage: "sidebar.leading")
                    }
                    .keyboardShortcut("s", modifiers: [.command, .control])
                    .disabled(servers.selected == nil || listPaneEmpty)
                }
            }
        }
    }

    private var listPaneEmpty: Bool {
        section == .activity && activity.typeCounts.isEmpty && activity.live.isEmpty
    }

    @ViewBuilder
    private var compactSplit: some View {
        if servers.selected == nil {
            NavigationStack {
                noServer
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .wellBackground()
                    .modifier(Header(title: title, entry: servers.selected, section: nil))
                    .navigationBarTitleDisplayMode(.inline)
            }
        } else {
            TabView(selection: sectionBinding) {
                ForEach(ServerSection.allCases) { item in
                    Tab(item.rawValue, systemImage: item.systemImage, value: item) {
                        NavigationStack {
                            compactList(item)
                                .navigationDestination(isPresented: pushBinding(item)) {
                                    compactDetail(item)
                                }
                        }
                        .environment(\.sectionIsActive, section == item)
                        .environment(\.connectionInTabBar, connectionInTabBar)
                    }
                }
            }
            .tabBarMinimizeBehavior(.onScrollDown)
            .tabViewBottomAccessory(isEnabled: section == .activity && connectionInTabBar) {
                ActivityConnectionControl()
                    .padding(.horizontal, 16)
            }
        }
    }

    private var connectionInTabBar: Bool {
        verticalSizeClass != .compact
    }

    private func compactList(_ item: ServerSection) -> some View {
        Group {
            if let entry = servers.selected {
                switch item {
                case .endpoints: EndpointListView(server: connected, serverID: entry.id)
                case .history: HistoryListView(serverID: entry.id)
                case .activity:
                    ActivityEventsView()
                        .modifier(SectionInspector(section: .activity, server: connected))
                case .mediaQuery: MediaQueryBuilderView(server: connected)
                }
            }
        }
        .id(servers.selected?.id)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .wellBackground()
        .environment(\.showSectionDetail, ShowSectionDetailAction { pushed.insert(item) })
        .modifier(Header(title: title, entry: servers.selected, section: nil))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if item == .endpoints {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        requests.requestPathFocus()
                    } label: {
                        Label("Edit Request", systemImage: "square.and.pencil")
                    }
                    .disabled(connected == nil)
                }
            }
        }
    }

    private func compactDetail(_ item: ServerSection) -> some View {
        Group {
            switch item {
            case .endpoints: WorkspaceView(editable: true)
            case .history: WorkspaceView(editable: false)
            case .mediaQuery: MediaResultsView(server: connected)
            case .activity: EmptyView()
            }
        }
        .modifier(SectionInspector(section: item, server: connected))
        .scrollEdgeEffectStyle(.soft, for: .top)
        .wellBackground()
        .navigationTitle(detailTitle(item))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detailTitle(_ item: ServerSection) -> String {
        switch item {
        case .endpoints, .history: "Request"
        case .mediaQuery: "Results"
        case .activity: ""
        }
    }

    private func pushBinding(_ item: ServerSection) -> Binding<Bool> {
        Binding(
            get: { pushed.contains(item) },
            set: { if $0 { pushed.insert(item) } else { pushed.remove(item) } }
        )
    }
    #endif

    /// macOS shows the title menu's chevron only on hover, so there the title is
    /// an explicit pull-down and the plain toolbar title is removed.
    private struct Header: ViewModifier {
        let title: String
        let entry: ServerStore.Entry?
        let section: Binding<ServerSection>?
        @State private var showInfo = false
        @Environment(\.sectionIsActive) private var isActive
        @Environment(\.isCompactWidth) private var compact
        #if os(iOS)
        @State private var showSettings = false
        #endif

        func body(content: Content) -> some View {
            content
                .navigationTitle(title)
                #if os(macOS)
                .toolbar(removing: .title)
                .toolbar {
                    if !title.isEmpty {
                        ToolbarItem(id: "window.server", placement: .navigation) {
                            Menu {
                                ServerMenu(showInfo: { showInfo = true })
                            } label: {
                                Text(title)
                                    .font(.headline)
                            }
                            .menuIndicator(.visible)
                            .help("Switch server")
                        }
                    }
                }
                #else
                .toolbarTitleMenu { ServerMenu(showInfo: { showInfo = true }, showSettings: { showSettings = true }) }
                .sheet(isPresented: $showSettings) { SettingsView() }
                .focusedSceneValue(\.showSettings, isActive ? ShowSettingsAction { showSettings = true } : nil)
                #endif
                .toolbar {
                    if let section {
                        ToolbarItem(id: "window.section", placement: .secondaryAction) {
                            SectionPicker(section: section)
                                .fixedSize()
                        }
                        #if os(iOS)
                        // A segmented control draws its own glass track; the
                        // bar's shared capsule behind it doubles it on iOS.
                        .sharedBackgroundVisibility(.hidden)
                        #endif
                    }
                }
                .popover(
                    isPresented: $showInfo,
                    attachmentAnchor: compact ? .point(.top) : .rect(.rect(CGRect(x: 48, y: 0, width: 1, height: 1))),
                    arrowEdge: .top
                ) {
                    if let entry {
                        ServerInfoView(entry: entry)
                            .presentationCompactAdaptation(.popover)
                    }
                }
                .focusedSceneValue(\.showServerInfo, entry == nil || !isActive ? nil : ShowServerInfoAction { showInfo = true })
        }
    }

    @ViewBuilder
    private var sectionList: some View {
        if let entry = servers.selected {
            ZStack {
                EndpointListView(server: connected, serverID: entry.id)
                    .sectionResident(active: section == .endpoints)
                HistoryListView(serverID: entry.id)
                    .sectionResident(active: section == .history)
                ActivityFiltersView()
                    .sectionResident(active: section == .activity)
                MediaQueryBuilderView(server: connected)
                    .sectionResident(active: section == .mediaQuery)
            }
            .id(entry.id)
            .scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            noServer
        }
    }

    private var noServer: some View {
        ContentUnavailableView(
            "No Server Selected",
            systemImage: "server.rack",
            description: Text("Choose a server from the title menu.")
        )
    }

    /// `.automatic` can resolve to the hard edge style, which fills the toolbar while the pointer is over the scroll view.
    /// Toolbar items declared from inside a section's content fill the toolbar the same way, so the detail declares them here.
    private var detailPane: some View {
        ZStack {
            WorkspaceView(editable: section == .endpoints)
                .sectionResident(active: section == .endpoints || section == .history)
            ActivityEventsView()
                .sectionResident(active: section == .activity)
            MediaResultsView(server: connected)
                .sectionResident(active: section == .mediaQuery)
        }
        .modifier(SectionInspector(section: section, server: connected))
        .scrollEdgeEffectStyle(.soft, for: .top)
        .toolbar {
            if section == .activity {
                ActivityToolbarItems()
            } else {
                RequestToolbarItems(server: connected)
            }
        }
        .wellBackground()
    }

    @ViewBuilder
    private var connectionStatus: some View {
        if stillConnecting {
            ZeroState(text: connectingText) {
                ProgressView()
            }
        } else if servers.entries.isEmpty {
            ContentUnavailableView {
                Label("No Servers", systemImage: "server.rack")
            } description: {
                Text("No Plex Media Servers on your account yet. Add one, then refresh.")
            } actions: {
                Button("Refresh Servers") { refreshServers() }
            }
        } else if let entry = servers.selected, !entry.resource.connections.contains(where: \.isHTTPS) {
            ContentUnavailableView {
                Label("No Secure Connection", systemImage: "lock.slash")
            } description: {
                Text("\(entry.resource.name) doesn't offer encrypted connections, which the app requires. In its Network settings, set Secure connections to Preferred, then refresh.")
            } actions: {
                Button("Refresh Servers") { refreshServers() }
            }
        } else {
            ContentUnavailableView {
                Label("Can't Reach Your Servers", systemImage: "wifi.exclamationmark")
            } description: {
                Text("None of your servers answered over a secure connection. Check they're online. On a server's own network, your router may be blocking plex.direct addresses: allow them in its DNS rebinding protection.")
            } actions: {
                Button("Refresh Servers") { refreshServers() }
            }
        }
    }

    private var connectingText: String {
        if !servers.isRefreshing, let selected = servers.selected, selected.isProbing || selected.probes.isEmpty {
            return "Connecting to \(selected.resource.name)"
        }
        return "Finding your servers"
    }

    private func refreshServers() {
        guard let token = account.token else { return }
        Task { await servers.refresh(token: token) }
    }
}

#if os(iOS)
private struct ListDetailPanes<ListPane: View, DetailPane: View>: View {
    let showsList: Bool
    @ViewBuilder let list: ListPane
    @ViewBuilder let detail: DetailPane

    @AppStorage("sectionListWidth") private var storedWidth: Double?
    @GestureState private var dragTranslation: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let container = proxy.size.width
            let range = Self.widthRange(in: container)
            let resting = Self.clamp(storedWidth.map { CGFloat($0) } ?? min(container * 0.4, 460), to: range)
            let width = Self.clamp(resting + dragTranslation, to: range)
            HStack(spacing: 0) {
                if showsList {
                    list
                        .frame(width: width)
                        .transition(reduceMotion ? .opacity : .move(edge: .leading))
                    Color.clear
                        .frame(width: 1)
                        .overlay { handle(resting: resting, width: width, range: range, container: container) }
                        .zIndex(1)
                }
                detail
            }
            .wellBackground()
            .animation(.smooth, value: showsList)
            .animation(reduceMotion ? nil : .smooth, value: storedWidth)
        }
    }

    /// No wider than the rows' trailing padding, so it covers no content. The
    /// drag reads global translation because the handle moves with it.
    private func handle(resting: CGFloat, width: CGFloat, range: ClosedRange<CGFloat>, container: CGFloat) -> some View {
        Color.clear
            .frame(width: 20)
            .contentShape(.rect)
            .contentShape(.hoverEffect, Capsule().inset(by: 6))
            .hoverEffect(.highlight)
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .updating($dragTranslation) { value, state, _ in state = value.translation.width }
                    .onEnded { value in
                        storedWidth = Double(Self.clamp(resting + value.translation.width, to: range))
                    }
            )
            .onTapGesture(count: 2) { storedWidth = nil }
            .accessibilityElement()
            .accessibilityLabel("Section List Width")
            .accessibilityValue(Double(width / max(container, 1)).formatted(.percent.precision(.fractionLength(0))))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: storedWidth = Double(Self.clamp(resting + 40, to: range))
                case .decrement: storedWidth = Double(Self.clamp(resting - 40, to: range))
                @unknown default: break
                }
            }
    }

    private static func widthRange(in container: CGFloat) -> ClosedRange<CGFloat> {
        let lower = min(260, container)
        return lower...max(lower, min(800, container - 360))
    }

    private static func clamp(_ width: CGFloat, to range: ClosedRange<CGFloat>) -> CGFloat {
        min(max(width, range.lowerBound), range.upperBound)
    }
}
#endif
