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
    /// Brings the section's detail on screen after its list acts. Set only
    /// where the detail isn't already beside the list: a compact width, which
    /// pushes it.
    @Entry var showSectionDetail: ShowSectionDetailAction? = nil
    /// Where Media's posters register as zoom sources, so the item sheet
    /// grows out of the one tapped. Set by `SectionInspector` on iOS.
    @Entry var posterZoom: Namespace.ID? = nil
}

struct ShowSectionDetailAction {
    let run: () -> Void

    func callAsFunction() { run() }
}

/// A section list's text filter. A compact width takes the system search
/// field. Wider layouts pin a field atop the list instead: on macOS the
/// system field is a toolbar item, so entering the section reconfigured the
/// window toolbar and reflowed the section switcher mid-animation.
private struct ListFilter<Actions: View>: ViewModifier {
    @Binding var text: String
    let prompt: String
    let actions: Actions?

    @Environment(\.isCompactWidth) private var compact

    /// A regular-width iPad has one bar spanning both panes, which would put
    /// the list's own actions at its far end over the detail, so there they
    /// sit beside the field; everywhere else they're in the bar over the list.
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

    func body(content: Content) -> some View {
        content.sectionListToolbar {
            if let actions {
                ToolbarItemGroup(placement: .primaryAction) { actions }
            }
        }
    }
}

extension View {
    /// Filters a section list by `text`; `actions` are the list's own sort
    /// and clear controls, placed per platform.
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
    let items: Items

    /// The toolbar stays attached whatever the section: branching around
    /// `.toolbar` gives the wrapped view a new identity on every switch. The
    /// Mac keeps the items and hides them, so a switch doesn't build and tear
    /// down toolbar items (a menu's included); iOS can't hide toolbar items,
    /// so there they come and go inside the builder.
    func body(content: Content) -> some View {
        let shown = visible && active
        #if os(macOS)
        content.toolbar { items.hidden(!shown) }
        #else
        content.toolbar {
            if shown { items }
        }
        #endif
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
/// whichever sibling SwiftUI read last. On a compact width each tab's detail
/// hosts its own, and only the active tab's presents. On iOS a Media item
/// opens in a sheet that zooms out of its poster wherever the detail is
/// compact or taller than wide: a side panel there squeezes the poster grid,
/// and an inspector can't zoom. Only the side inspector lets another poster
/// be tapped past it; a sheet closes back into its poster first.
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
    /// Where the event and item sheets rest. Each opens at half height and
    /// is dragged taller from there; an event sheet keeps its height while
    /// another event is picked behind it. Both start at half again next time.
    @State private var eventDetent: PresentationDetent = .medium
    @State private var itemDetent: PresentationDetent = .medium

    private enum Shown {
        case event(NotificationEvent)
        case item(MediaItem)
    }

    // Resolved in the body, not in the binding or content closures, so
    // Observation ties this view to exactly the state it presents.
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

    func body(content: Content) -> some View {
        let shown = shown
        let isActive = isActive
        let itemInSheet = itemInSheet
        let sheetItem: MediaItem? = if itemInSheet, case .item(let item) = shown { item } else { nil }
        let inspected = sheetItem == nil ? shown : nil
        content
            #if os(iOS)
            // UIKit hosts an inspector's main content in its own opaque
            // container, which covers a well drawn behind the modifier.
            .background { WellBackground() }
            .environment(\.posterZoom, posterZoom)
            #endif
            .inspector(isPresented: Binding(get: { inspected != nil }, set: { if !$0, isActive, sheetItem == nil { dismiss() } })) {
                switch inspected {
                case .event(let event):
                    EventInspector(event: event)
                        .inspectorColumnWidth(min: 320, ideal: 460, max: 800)
                        // Where the inspector adapts to a sheet or an overlay
                        // (compact width, a portrait or split-screen iPad), the
                        // list stays live behind it so another tap re-targets it
                        // instead of first dismissing it; a half-height sheet
                        // leaves the list in view to tap.
                        .presentationDetents([.medium, .large], selection: $eventDetent)
                        .presentationDragIndicator(.visible)
                        .presentationBackgroundInteraction(.enabled)
                case .item(let item):
                    mediaInfo(item)
                        .inspectorColumnWidth(min: 280, ideal: 340, max: 480)
                case nil:
                    EmptyView()
                }
            }
            #if os(iOS)
            // The window's lightbox is drawn under a sheet; the sheet needs
            // its own.
            .sheet(isPresented: Binding(get: { sheetItem != nil }, set: { if !$0, isActive, itemInSheet { dismiss() } })) {
                if let sheetItem {
                    mediaInfo(sheetItem, showsPoster: true)
                        .overlay { LightboxOverlay() }
                        .presentationDetents([.medium, .large], selection: $itemDetent)
                        .presentationDragIndicator(.visible)
                        .navigationTransition(.zoom(sourceID: sheetItem.id, in: posterZoom))
                }
            }
            .onGeometryChange(for: Bool.self) { $0.size.height > $0.size.width } action: { tall = $0 }
            #endif
            .onChange(of: inspected == nil) { _, closed in
                if closed { eventDetent = .medium }
            }
            .onChange(of: sheetItem == nil) { _, closed in
                if closed { itemDetent = .medium }
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
    /// Every section's list in the column: inset rows over the column's own
    /// background, never an opaque list background of its own — on macOS the
    /// column is a sidebar and its material should show through.
    func sectionListStyle() -> some View {
        listStyle(.inset)
            .scrollContentBackground(.hidden)
    }

    /// A row of a `sectionListStyle` list. iOS gives inset rows an opaque
    /// cell background, which covers the well; the Mac's are already clear.
    /// A selected row keeps an accent tint, as `sectionColumnRow` draws it.
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

    /// A row that's a button rather than the list's selection (Activity's
    /// sessions), so it tints itself when chosen on the Mac too, where no
    /// list selection draws it.
    func sectionListButtonRow(selected: Bool) -> some View {
        listRowBackground(
            RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Color.accentColor.opacity(0.22) : .clear)
                .padding(.horizontal, 8)
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The column for a long section (the endpoint catalog, a deep history).
/// `List` on macOS hosts every row in its own `NSHostingView` and measures
/// them all when the list appears, so hundreds of rows stall each section
/// switch; iPadOS's list is lazy and never did. A `LazyVStack` realizes only
/// what's on screen on both. Short columns (Activity, Media) keep `List`.
/// A compact width is always iOS, so it takes the lazy `List`: rows swipe
/// there, and a stack can't. Scrolling ends the filter field's editing at
/// once, so a field left focused with its keyboard hidden can't hold on to
/// the drag.
struct SectionColumnList<Content: View>: View {
    @ViewBuilder let content: () -> Content

    @Environment(\.isCompactWidth) private var compact

    var body: some View {
        if compact {
            List {
                Group { content() }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    content()
                }
                .padding(.vertical, 6)
            }
            .scrollDismissesKeyboard(.immediately)
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
            .listRowInsets(EdgeInsets())
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
    @Environment(ActivityStore.self) private var activity
    @AppStorage("serverSection") private var section: ServerSection = .endpoints
    @State private var hasConnected = false
    #if os(macOS)
    @State private var columns: NavigationSplitViewVisibility = .all
    #else
    @AppStorage("sectionListVisible") private var sectionListVisible = true
    @Environment(\.isCompactWidth) private var compact
    /// The sections whose detail is pushed over their list on a compact width.
    @State private var pushed: Set<ServerSection> = []
    #endif

    private var connected: ConnectedServer? {
        servers.selected.flatMap { servers.connectedServer(for: $0) }
    }

    /// Discovery or probing still in flight before any server has connected.
    private var stillConnecting: Bool {
        servers.isRefreshing || servers.entries.contains { $0.isProbing || $0.probes.isEmpty }
    }

    /// Before the first connection this session there's nothing to list,
    /// switch, or name, so the window is only the status — no sidebar, no
    /// switcher — the HIG alternative to a splash. Once connected, per-server
    /// states take over and a later switch never falls back here.
    private var isInitialLoad: Bool { !hasConnected && connected == nil }

    /// Empty while the first discovery runs: the selection is remembered
    /// from last time, and its name would claim a server before one's found.
    private var title: String {
        if isInitialLoad, servers.isRefreshing { return "" }
        return servers.selected?.resource.name ?? "Servers"
    }

    /// A section change swaps in that section's own workspace *before* its
    /// view is built — not reactively after. Otherwise the incoming
    /// Endpoints/History detail builds `ResponseView`/`CodeTextView` for the
    /// outgoing section's response (an `NSTextView` on macOS) only to tear it
    /// down when the swap lands, stalling the switch. Each section keeps its
    /// request and response, so a compact width's pushed details stay pushed.
    private var sectionBinding: Binding<ServerSection> {
        Binding(
            get: { section },
            set: { newValue in
                guard newValue != section else { return }
                requests.switchWorkspace(from: section.rawValue, to: newValue.rawValue)
                section = newValue
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
            .background { WellBackground() }
            .modifier(Header(title: title, entry: servers.selected, section: nil))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
    }

    #if os(iOS)

    /// iPad has no window-wide toolbar over split columns, so the list and
    /// detail are two panes under one navigation bar. The `.editor` role is
    /// what keeps the title leading with `.secondaryAction` in the centre,
    /// matching the Mac toolbar.
    private var regularSplit: some View {
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

    /// A compact width (an iPhone, a narrow iPad split) can't hold the list
    /// beside its detail, or the switcher beside the title, so each section
    /// is a tab: its list at the root, its detail pushed. The tabs replace
    /// the switcher, not the title — the server is still the title menu in
    /// every tab.
    @ViewBuilder
    private var compactSplit: some View {
        if servers.selected == nil {
            NavigationStack {
                noServer
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background { WellBackground() }
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
                    }
                }
            }
            .tabBarMinimizeBehavior(.onScrollDown)
            // Activity's connection rides the tab bar as its accessory: the
            // system's glass at the bar's width, inline beside it when the
            // bar minimizes on scroll.
            .tabViewBottomAccessory(isEnabled: section == .activity) {
                ActivityConnectionControl()
                    .padding(.horizontal, 16)
            }
        }
    }

    private func compactList(_ item: ServerSection) -> some View {
        Group {
            if let entry = servers.selected {
                switch item {
                case .endpoints: EndpointListView(server: connected, serverID: entry.id)
                case .history: HistoryListView(serverID: entry.id)
                // The list pane only filters the events, which a toolbar menu
                // does here, so the events are the tab's root and nothing
                // is pushed.
                case .activity:
                    ActivityEventsView()
                        .modifier(SectionInspector(section: .activity, server: connected))
                case .mediaQuery: MediaQueryBuilderView(server: connected)
                }
            }
        }
        .id(servers.selected?.id)
        // The tab bar crossfades whole tabs; cutting the outgoing content
        // leaves it only the well to fade, so the switch reads as the
        // regular layout's does.
        .sectionResident(active: section == item)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .background { WellBackground() }
        .environment(\.showSectionDetail, ShowSectionDetailAction { pushed.insert(item) })
        .modifier(Header(title: title, entry: servers.selected, section: nil))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The request bar is pushed, so a path can be typed without
            // picking an endpoint first. Same action as Focus Path (⌘L).
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
        .sectionResident(active: section == item)
        .modifier(SectionInspector(section: item, server: connected))
        .scrollEdgeEffectStyle(.soft, for: .top)
        .background { WellBackground() }
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

    /// Title leading (the server, with its menu), section switcher centre.
    /// Server Info… is a menu item, so its popover drops from the title area.
    /// iPad's title menu shows its chevron permanently; macOS's only on hover,
    /// so there the title is an explicit pull-down and the plain toolbar
    /// title is removed (the window keeps its title for Mission Control and
    /// the Window menu). iPadOS has no Settings scene, so Settings… presents
    /// a sheet from here, reached from the title menu or the menu bar. On a
    /// compact width every tab's root carries one, without the switcher, and
    /// only the active tab's publishes its commands.
    private struct Header: ViewModifier {
        let title: String
        let entry: ServerStore.Entry?
        /// The section switcher; nil where tabs switch sections instead.
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
                }
                #else
                .toolbarTitleMenu { ServerMenu(showInfo: { showInfo = true }, showSettings: { showSettings = true }) }
                .sheet(isPresented: $showSettings) { SettingsView() }
                .focusedSceneValue(\.showSettings, isActive ? ShowSettingsAction { showSettings = true } : nil)
                #endif
                .toolbar {
                    if let section {
                        ToolbarItem(placement: .secondaryAction) {
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
                // A compact bar centres its title, so the popover points at
                // the middle rather than the leading title.
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

    /// Soft edge on both panes: `.automatic` can resolve to the hard style,
    /// which fills the toolbar while the pointer is over the scroll view even
    /// with nothing scrolled beneath it. Soft only blurs what actually passes
    /// under the bar.
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
        .background { WellBackground() }
    }

    /// The shell's content before the first connection: a spinner while
    /// discovery/probing runs, then a resolvable empty state.
    @ViewBuilder
    private var connectionStatus: some View {
        if stillConnecting {
            ZeroState(text: servers.isRefreshing ? "Finding your servers" : "Connecting to \(servers.selected?.resource.name ?? "your server")") {
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
/// detail below its minimum. One well spans both panes, so the list sits on
/// the same backdrop as the detail with no seam where they meet.
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
            .background { WellBackground() }
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
