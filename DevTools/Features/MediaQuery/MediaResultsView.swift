import SwiftUI

enum MediaResultsTab: String, CaseIterable, Identifiable {
    case posters = "Posters"
    case response = "Response"
    case headers = "Headers"

    var id: String { rawValue }
}

/// The Media section's result pane: the query's items as a poster grid, with
/// the raw response and headers a tab away. Clicking a poster selects it and
/// opens its metadata in the inspector.
struct MediaResultsView: View {
    let server: ConnectedServer?

    @Environment(RequestStore.self) private var requests
    @Environment(\.sectionIsActive) private var isActive
    @AppStorage("mediaResultsTab") private var tab: MediaResultsTab = .posters
    @Environment(MediaQueryStore.self) private var mediaQuery
    @State private var collapsed: Set<Int> = []

    private var items: [MediaItem] {
        requests.document?.tree?.children.map(MediaItem.init) ?? []
    }

    /// The field the shown results are ordered by, from the request that
    /// produced them — not the builder's current pick, which may have changed
    /// since the query ran.
    private var sortKey: String? {
        requests.lastSent?.query.first { $0.enabled && $0.name == "sort" }?.value
            .split(separator: ",").first?
            .split(separator: ":").first
            .map(String.init)
    }

    var body: some View {
        // Resting, error, and no-items states transition; results arrive
        // without one — the grid runs its own entrance, and the body can't
        // take one.
        ZStack {
            if let response = requests.response {
                Group {
                    switch tab {
                    case .posters:
                        ZStack {
                            if requests.document == nil {
                                FillingScrollView {
                                    headerBlock
                                    ProgressView()
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                                .transition(.identity)
                            } else if items.isEmpty {
                                FillingScrollView {
                                    headerBlock
                                    ContentUnavailableView(
                                        "No Items",
                                        systemImage: "square.grid.3x3",
                                        description: Text("The query matched nothing. Loosen a filter and run it again.")
                                    )
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                                .restingStateTransition()
                                .zIndex(1)
                            } else {
                                grid
                                    .transition(.identity)
                            }
                        }
                    case .response:
                        if let document = requests.document {
                            RawResponseView(document: document, response: response, collapsed: $collapsed) {
                                headerBlock
                            }
                        } else {
                            FillingScrollView {
                                headerBlock
                                ProgressView()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                    case .headers:
                        HeadersView(response: response, server: server, editable: false) {
                            headerBlock
                        }
                    }
                }
                .transition(.identity)
            } else {
                FillingScrollView {
                    headerBlock
                    ZStack {
                        if let error = requests.errorMessage {
                            ContentUnavailableView(
                                "Request Failed",
                                systemImage: "exclamationmark.triangle",
                                description: Text(error)
                            )
                            .restingStateTransition(rising: true)
                        } else {
                            ZeroState(text: "Run a query to see its items as posters.")
                                .restingStateTransition(rising: true)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .restingStateTransition()
                .zIndex(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: requests.response?.receivedAt) { _, _ in
            mediaQuery.selectedItemID = nil
            mediaQuery.showsItemInfo = false
            collapsed = []
        }
        .focusedSceneValue(
            \.showMediaInfo,
            isActive && mediaQuery.selectedItemID != nil
                ? ShowMediaInfoAction(visible: mediaQuery.showsItemInfo) { mediaQuery.showsItemInfo.toggle() }
                : nil
        )
    }

    private var headerBlock: some View {
        VStack(spacing: 0) {
            RequestSummaryBar(server: server)
            if let response = requests.response {
                Divider()
                ResponseInfoRow(
                    response: response,
                    pagination: requests.pagination,
                    server: server,
                    controls: tab == .response ? requests.document.map { BodyControls(document: $0, response: response) } : nil
                ) {
                    Picker("View", selection: $tab) {
                        ForEach(MediaResultsTab.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
        .background(.fill.tertiary, in: .rect(cornerRadius: 12))
        .padding(12)
    }

    private var grid: some View {
        ScrollView {
            headerBlock
            PosterGrid(items: items, server: server, sortKey: sortKey, selectedID: mediaQuery.selectedItemID) { id in
                mediaQuery.selectedItemID = id
                mediaQuery.showsItemInfo = true
            }
            .id(requests.response?.receivedAt)
        }
    }
}

/// The query's items as a poster grid. Cells rise and fade in with a short
/// positional stagger so a fresh result set reads as arriving rather than
/// blinking into place; the `.id(receivedAt)` in the parent remounts this so
/// the entrance replays on each new query but not on scroll or section switch.
private struct PosterGrid: View {
    let items: [MediaItem]
    let server: ConnectedServer?
    let sortKey: String?
    let selectedID: Int?
    let select: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 130, maximum: 150), spacing: 16, alignment: .top)],
            alignment: .leading,
            spacing: 20
        ) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                PosterCell(item: item, server: server, sortKey: sortKey, isSelected: item.id == selectedID) {
                    select(item.id)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared || reduceMotion ? 0 : 8)
                .animation(
                    reduceMotion
                        ? .smooth(duration: 0.2)
                        : .smooth(duration: 0.4).delay(Double(min(index, 10)) * 0.035),
                    value: appeared
                )
            }
        }
        .padding(16)
        .onAppear { appeared = true }
    }
}

private struct PosterCell: View {
    let item: MediaItem
    let server: ConnectedServer?
    let sortKey: String?
    let isSelected: Bool
    let select: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 6) {
                PosterArt(item: item, server: server)
                    .overlay {
                        ZStack {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(.tint, lineWidth: 3)
                                    .transition(.opacity.combined(with: .scale(reduceMotion ? 1 : 1.04)))
                            }
                        }
                        .animation(.bouncy, value: isSelected)
                    }
                Text(item.caption(sortedBy: sortKey))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(width: PosterArt.width, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(PosterButtonStyle())
        .help(item.title)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct PosterButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
            .opacity(pressed && reduceMotion ? 0.7 : 1)
            .animation(.snappy(duration: 0.15), value: pressed)
    }
}

/// An item's artwork as the grid shows it.
struct PosterArt: View {
    let item: MediaItem
    let server: ConnectedServer?

    static let width: CGFloat = 130

    static func size(for shape: MediaItem.Shape) -> CGSize {
        switch shape {
        case .poster: CGSize(width: width, height: width * 1.5)
        case .square: CGSize(width: width, height: width)
        case .wide: CGSize(width: width, height: width * 9 / 16)
        }
    }

    private var symbol: String {
        switch item.type {
        case "show", "season", "episode": "tv"
        case "artist": "music.mic"
        case "album", "track": "music.note"
        case "photo", "photoalbum": "photo"
        case "collection": "rectangle.stack"
        case "playlist": "music.note.list"
        default: "film"
        }
    }

    var body: some View {
        RemoteImage(value: item.thumb, server: server, size: Self.size(for: item.shape)) {
            Rectangle()
                .fill(.quaternary)
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
        }
        .clipShape(.rect(cornerRadius: 8))
    }
}
