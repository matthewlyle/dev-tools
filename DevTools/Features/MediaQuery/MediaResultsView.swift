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
    @Environment(PosterFlightStore.self) private var flights
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("mediaResultsTab") private var tab: MediaResultsTab = .posters
    @State private var selectedID: Int?
    @State private var showInfo = false
    @State private var collapsed: Set<Int> = []

    private var items: [MediaItem] {
        requests.document?.tree?.children.map(MediaItem.init) ?? []
    }

    private var selected: MediaItem? {
        items.first { $0.id == selectedID }
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
        // Resting, error, and no-items states fade out; results arrive without
        // one — the grid runs its own entrance, and the body can't take one.
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
                                .transition(.opacity)
                                .zIndex(1)
                            } else {
                                grid
                                    .transition(.identity)
                            }
                        }
                        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: items.isEmpty)
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
                        } else {
                            ZeroState(text: "Run a query to see its items as posters.")
                        }
                    }
                    .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: requests.errorMessage != nil)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: requests.response != nil)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .inspector(isPresented: $showInfo) {
            if let selected {
                MediaInfoView(item: selected, server: server) { showInfo = false }
                    .inspectorColumnWidth(min: 280, ideal: 340, max: 480)
            }
        }
        .onChange(of: requests.response?.receivedAt) { _, _ in
            selectedID = nil
            showInfo = false
            collapsed = []
        }
        .onChange(of: showInfo) { _, shown in
            if !shown { flights.land() }
        }
        .onChange(of: isActive) { _, active in
            if !active { flights.land() }
        }
        .focusedSceneValue(
            \.showMediaInfo,
            isActive && selectedID != nil ? ShowMediaInfoAction(visible: showInfo) { showInfo.toggle() } : nil
        )
    }

    private var headerBlock: some View {
        VStack(spacing: 0) {
            RequestSummaryBar(server: server)
            if let response = requests.response {
                Divider()
                HStack(spacing: 10) {
                    ResponseStatusBar(response: response)
                    if let pagination = requests.pagination {
                        PaginationControls(pagination: pagination, server: server)
                    }
                    Spacer()
                    if tab == .response, let document = requests.document {
                        BodyControls(document: document, response: response)
                    }
                    Picker("View", selection: $tab) {
                        ForEach(MediaResultsTab.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .background(.fill.tertiary, in: .rect(cornerRadius: 12))
        .padding(12)
    }

    private var grid: some View {
        ScrollView {
            headerBlock
            PosterGrid(items: items, server: server, sortKey: sortKey, selectedID: selectedID) { item, frame in
                select(item, from: frame)
            }
            .id(requests.response?.receivedAt)
        }
    }

    private func select(_ item: MediaItem, from frame: CGRect) {
        let alreadyShown = showInfo && selectedID == item.id
        if !alreadyShown, !reduceMotion, let server, let thumb = item.thumb {
            flights.launch(.init(itemID: item.id, thumb: thumb, server: server, size: PosterArt.size(for: item.shape), source: frame))
        }
        selectedID = item.id
        showInfo = true
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
    let select: (MediaItem, CGRect) -> Void

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
                    select(item, $0)
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
    let select: (CGRect) -> Void

    @State private var artFrame: CGRect = .zero

    var body: some View {
        Button {
            select(artFrame)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                PosterArt(item: item, server: server)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { artFrame = $0 }
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.tint, lineWidth: 3)
                        }
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
        .buttonStyle(.plain)
        .help(item.title)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// An item's artwork as the grid shows it. The inspector hero uses the same
/// size so the poster flight between them is a pure move and the hero's
/// decode is an `ImageStore` cache hit on the grid's pixels.
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
