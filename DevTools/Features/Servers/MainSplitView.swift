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

/// Whether the section-list column is showing. Its toolbar items act on that
/// list, so they leave the window's toolbar with it — on macOS a collapsed
/// column's view stays alive and would otherwise keep contributing them.
extension EnvironmentValues {
    @Entry var sectionListVisible = true
    /// Whether this section is the one the switcher shows. Every section stays
    /// mounted so switching is instant; an inactive one must not publish
    /// toolbar items or focused commands, or Send/Delete would act on a
    /// section that isn't on screen.
    @Entry var sectionIsActive = true
}

/// A filter field pinned atop a section list. Endpoints and History filter
/// in place rather than through `.searchable`: on macOS its search field is a
/// toolbar item, so entering those sections reconfigured the window toolbar
/// and reflowed the section switcher mid-animation.
struct ListFilterField<Actions: View>: View {
    @Binding var text: String
    let prompt: String
    private let actions: Actions?

    init(text: Binding<String>, prompt: String, @ViewBuilder actions: () -> Actions) {
        _text = text
        self.prompt = prompt
        self.actions = actions()
    }

    var body: some View {
        placed
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    /// The list's own actions (sort, clear) sit over the list on both
    /// platforms: toolbar items over its column on macOS; on iPad, whose one
    /// bar spans both panes and would push them to its far end, beside the
    /// field.
    @ViewBuilder
    private var placed: some View {
        #if os(macOS)
        if let actions {
            field.sectionListToolbar {
                ToolbarItemGroup(placement: .primaryAction) { actions }
            }
        } else {
            field
        }
        #else
        HStack(spacing: 12) {
            field
            if let actions {
                actions
                    .labelStyle(.iconOnly)
                    .imageScale(.large)
            }
        }
        #endif
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

extension ListFilterField where Actions == EmptyView {
    init(text: Binding<String>, prompt: String) {
        _text = text
        self.prompt = prompt
        actions = nil
    }
}

private struct SectionListToolbar<Items: ToolbarContent>: ViewModifier {
    @Environment(\.sectionListVisible) private var visible
    @Environment(\.sectionIsActive) private var active
    let items: Items

    func body(content: Content) -> some View {
        if visible && active {
            content.toolbar { items }
        } else {
            content
        }
    }
}

/// Keeps a section's views mounted while another is showing, so switching
/// never rebuilds them. The hidden section is transparent, untouchable, out
/// of the accessibility tree, and disabled so nothing in it can take
/// keyboard focus.
private struct SectionResident: ViewModifier {
    let active: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        // Only the incoming section moves. The outgoing one leaves at once:
        // the toolbar's edge effect already belongs to the new section, so a
        // fading-out section shows through the toolbar unblurred. The
        // body-scoped animation touches only the opacity, because the section
        // flag flows into toolbar items and focused values, which must swap
        // in the same frame.
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
            .disabled(!active)
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
    func sectionListToolbar<Items: ToolbarContent>(@ToolbarContentBuilder items: () -> Items) -> some View {
        modifier(SectionListToolbar(items: items()))
    }
}

/// The detail pane's one inspector, showing whatever the visible section has
/// open: an Activity event's payload or a Media item's info. Sections are
/// resident siblings, and two `.inspector` modifiers in one column compete
/// for the same presentation, so a section's own would present or fill from
/// whichever sibling SwiftUI read last.
private struct SectionInspector: ViewModifier {
    let section: ServerSection
    let server: ConnectedServer?

    @Environment(ActivityStore.self) private var activity
    @Environment(MediaQueryStore.self) private var mediaQuery
    @Environment(RequestStore.self) private var requests

    private enum Shown {
        case event(NotificationEvent)
        case item(MediaItem)
    }

    // Resolved in the body, not in the binding or content closures, so
    // Observation ties this view to exactly the state it presents.
    private var shown: Shown? {
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

    func body(content: Content) -> some View {
        let shown = shown
        content.inspector(isPresented: Binding(get: { shown != nil }, set: { if !$0 { dismiss() } })) {
            switch shown {
            case .event(let event):
                EventInspector(event: event)
                    .inspectorColumnWidth(min: 320, ideal: 460, max: 800)
                    // Where the inspector adapts to a sheet or an overlay
                    // (compact width, a portrait or split-screen iPad), the
                    // list stays live behind it so another tap re-targets it
                    // instead of first dismissing it.
                    .presentationBackgroundInteraction(.enabled)
            case .item(let item):
                MediaInfoView(item: item, server: server) { mediaQuery.showsItemInfo = false }
                    .inspectorColumnWidth(min: 280, ideal: 340, max: 480)
                    .presentationBackgroundInteraction(.enabled)
            case nil:
                EmptyView()
            }
        }
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
    /// Every section's list in the column: inset rows over the column's own
    /// background, never an opaque list background of its own — on macOS the
    /// column is a sidebar and its material should show through.
    func sectionListStyle() -> some View {
        listStyle(.inset)
            .scrollContentBackground(.hidden)
    }
}

/// The column for a long section (the endpoint catalog, a deep history).
/// `List` on macOS hosts every row in its own `NSHostingView` and measures
/// them all when the list appears, so hundreds of rows stall each section
/// switch; iPadOS's list is lazy and never did. A `LazyVStack` realizes only
/// what's on screen on both. Short columns (Activity, Media) keep `List`.
struct SectionColumnList<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(.vertical, 6)
        }
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
    }
}

extension View {
    /// Inset-list row metrics for a `SectionColumnList` row, with the
    /// selected row tinted the way an inset list highlights it.
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
        // Segmented while it fits the toolbar; a labelled pop-up when the
        // window is too narrow, so a collapsed switcher still shows the
        // current section and every choice (a segmented control renders
        // unusably in the toolbar overflow menu).
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
    @AppStorage("serverSection") private var section: ServerSection = .endpoints
    @State private var hasConnected = false
    #if os(macOS)
    @State private var columns: NavigationSplitViewVisibility = .all
    #else
    @AppStorage("sectionListVisible") private var sectionListVisible = true
    #endif

    private var connected: ConnectedServer? {
        servers.selected.flatMap { servers.connectedServer(for: $0) }
    }

    /// Discovery or probing still in flight before any server has connected.
    private var stillConnecting: Bool {
        servers.isRefreshing || servers.entries.contains { $0.isProbing || $0.probes.isEmpty }
    }

    /// Before the first connection this session the shell is up but has no
    /// content yet, so it shows an inline loading/empty state in the detail —
    /// the HIG alternative to a splash. Once connected, per-server states take
    /// over and a later switch never falls back here.
    private var isInitialLoad: Bool { !hasConnected && connected == nil }

    private var title: String { servers.selected?.resource.name ?? "Servers" }

    /// Section changes reset the workspace *before* the new section's view is
    /// built — not reactively after. Otherwise the incoming Endpoints/History
    /// detail builds `ResponseView`/`CodeTextView` for the previous response
    /// (an `NSTextView` on macOS) only to tear it down when the reset lands,
    /// stalling the switch.
    private var sectionBinding: Binding<ServerSection> {
        Binding(
            get: { section },
            set: { newValue in
                guard newValue != section else { return }
                requests.reset()
                section = newValue
            }
        )
    }

    var body: some View {
        split
            .task(id: connected?.machineID) {
                if let connected { await requests.preloadOptions(on: connected) }
            }
            .onChange(of: servers.selectedID) { _, _ in
                requests.reset()
            }
            .onChange(of: connected?.machineID, initial: true) { _, id in
                if id != nil { hasConnected = true }
            }
            .onChange(of: section, initial: true) { _, section in
                requests.recordsNavigation = section != .mediaQuery
            }
    }

    #if os(macOS)
    private var split: some View {
        NavigationSplitView(columnVisibility: $columns) {
            sectionList
                .navigationSplitViewColumnWidth(min: 260, ideal: 340, max: 800)
                .environment(\.sectionListVisible, columns != .detailOnly)
        } detail: {
            detailPane
                .modifier(Header(title: title, entry: servers.selected, section: sectionBinding))
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
                    ListDetailPanes(showsList: sectionListVisible) {
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
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        sectionListVisible.toggle()
                    } label: {
                        Label(sectionListVisible ? "Hide Section List" : "Show Section List", systemImage: "sidebar.leading")
                    }
                    .keyboardShortcut("s", modifiers: [.command, .control])
                    .disabled(servers.selected == nil)
                }
            }
        }
    }
    #endif

    /// Title leading (the server, with its menu), section switcher centre.
    /// Server Info… is a menu item, so its popover drops from the title area.
    /// iPad's title menu shows its chevron permanently; macOS's only on hover,
    /// so there the title is an explicit pull-down and the plain toolbar
    /// title is removed (the window keeps its title for Mission Control and
    /// the Window menu). iPadOS has no Settings scene, so Settings… presents
    /// a sheet from here, reached from the title menu or the menu bar.
    private struct Header: ViewModifier {
        let title: String
        let entry: ServerStore.Entry?
        @Binding var section: ServerSection
        @State private var showInfo = false
        #if os(iOS)
        @State private var showSettings = false
        #endif

        func body(content: Content) -> some View {
            content
                .navigationTitle(title)
                #if os(macOS)
                .toolbar(removing: .title)
                .toolbar {
                    ToolbarItem(placement: .navigation) {
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
                #else
                .toolbarTitleMenu { ServerMenu(showInfo: { showInfo = true }, showSettings: { showSettings = true }) }
                .sheet(isPresented: $showSettings) { SettingsView() }
                .focusedSceneValue(\.showSettings, ShowSettingsAction { showSettings = true })
                #endif
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
        if isInitialLoad {
            Color.clear
        } else if let entry = servers.selected {
            ZStack {
                EndpointListView(server: connected, serverID: entry.id)
                    .sectionResident(active: section == .endpoints)
                HistoryListView(serverID: entry.id)
                    .sectionResident(active: section == .history)
                ActivityControlsView()
                    .sectionResident(active: section == .activity)
                MediaQueryBuilderView(server: connected)
                    .sectionResident(active: section == .mediaQuery)
            }
            .id(entry.id)
            .scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            ContentUnavailableView(
                "No Server Selected",
                systemImage: "server.rack",
                description: Text("Choose a server from the title menu.")
            )
        }
    }

    /// Soft edge on both panes: `.automatic` can resolve to the hard style,
    /// which fills the toolbar while the pointer is over the scroll view even
    /// with nothing scrolled beneath it. Soft only blurs what actually passes
    /// under the bar.
    @ViewBuilder
    private var detailPane: some View {
        Group {
            if isInitialLoad {
                connectionStatus
            } else {
                ZStack {
                    WorkspaceView(editable: section == .endpoints)
                        .sectionResident(active: section == .endpoints || section == .history)
                    ActivityEventsView()
                        .sectionResident(active: section == .activity)
                    MediaResultsView(server: connected)
                        .sectionResident(active: section == .mediaQuery)
                }
                .modifier(SectionInspector(section: section, server: connected))
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .background { WellBackground() }
    }

    /// The shell's content before the first connection: a spinner while
    /// discovery/probing runs, then a resolvable empty state.
    @ViewBuilder
    private var connectionStatus: some View {
        if stillConnecting {
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                Text(servers.isRefreshing ? "Finding your servers" : "Connecting to \(servers.selected?.resource.name ?? "your server")")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if servers.entries.isEmpty {
            ContentUnavailableView {
                Label("No Servers", systemImage: "server.rack")
            } description: {
                Text("No Plex Media Servers on your account yet. Add one, then refresh.")
            } actions: {
                Button("Refresh Servers") { refreshServers() }
            }
        } else {
            ContentUnavailableView {
                Label("Can't Reach Your Servers", systemImage: "wifi.exclamationmark")
            } description: {
                Text("None of your servers answered. Check they're online and on the same network, then try again.")
            } actions: {
                Button("Refresh Servers") { refreshServers() }
            }
        }
    }

    private func refreshServers() {
        guard let token = account.token else { return }
        Task { await servers.refresh(token: token) }
    }
}

#if os(iOS)
/// iPad's section list and detail side by side under the one navigation bar.
/// There is no split view column to resize, so the divider is the drag
/// handle `NavigationSplitView` gives macOS. The kept width re-clamps to the
/// window on every layout, so rotation or Split View never squeezes the
/// detail below its minimum.
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
                        .background(Self.listBackground)
                        .transition(reduceMotion ? .opacity : .move(edge: .leading))
                    Self.listBackground
                        .frame(width: 1)
                        .overlay { handle(resting: resting, width: width, range: range, container: container) }
                        .zIndex(1)
                }
                detail
            }
            .animation(.smooth, value: showsList)
            .animation(reduceMotion ? nil : .smooth, value: storedWidth)
        }
    }

    /// Wider than the hairline so it's easy to hit, but no wider than the
    /// rows' trailing padding, so it doesn't cover list or detail content.
    /// The drag reads global translation because the handle moves with it.
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

    private static var listBackground: Color { Color(uiColor: .secondarySystemBackground) }

    /// The list's minimum (never wider than the window), macOS's column
    /// maximum, and whatever leaves the detail its own minimum.
    private static func widthRange(in container: CGFloat) -> ClosedRange<CGFloat> {
        let lower = min(260, container)
        return lower...max(lower, min(800, container - 360))
    }

    private static func clamp(_ width: CGFloat, to range: ClosedRange<CGFloat>) -> CGFloat {
        min(max(width, range.lowerBound), range.upperBound)
    }
}
#endif
