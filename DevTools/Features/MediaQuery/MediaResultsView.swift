import SwiftUI

enum MediaResultsTab: String, CaseIterable, Identifiable {
    case posters = "Posters"
    case response = "Response"
    case headers = "Headers"

    var id: String { rawValue }
}

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

    private var sortKey: String? {
        requests.lastSent?.query.first { $0.enabled && $0.name == "sort" }?.value
            .split(separator: ",").first?
            .split(separator: ":").first
            .map(String.init)
    }

    var body: some View {
        // Hidden, it draws nothing: sections share the workspace, so a hidden
        // grid would lay out, and fetch art for, another section's response.
        ZStack {
            if !isActive {
                EmptyView()
            } else if let response = requests.response, let document = requests.document {
                Group {
                    switch tab {
                    case .posters:
                        ZStack {
                            if items.isEmpty {
                                FillingScrollView {
                                    headerBlock
                                    ZeroState(text: "The query matched nothing. Loosen a filter and run it again.")
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
                        RawResponseView(document: document, response: response, collapsed: $collapsed) {
                            headerBlock
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
                        } else if requests.isSending {
                            ProgressView()
                        } else {
                            ZeroState(text: "Run a query to see results here.")
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
        .requestScreenActions(server: server)
        .onChange(of: requests.document?.version) { _, _ in
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

private struct PosterGrid: View {
    let items: [MediaItem]
    let server: ConnectedServer?
    let sortKey: String?
    let selectedID: Int?
    let select: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isCompactWidth) private var compact
    @State private var appeared = false

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: compact ? 100 : 130), spacing: compact ? 12 : 16, alignment: .top)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
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
    @Environment(\.posterZoom) private var posterZoom

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 6) {
                PosterArt(item: item, server: server)
                    .zoomSource(id: item.id, in: posterZoom)
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
            .frame(maxWidth: .infinity, alignment: .leading)
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

private extension View {
    @ViewBuilder
    func zoomSource(id: some Hashable, in namespace: Namespace.ID?) -> some View {
        #if os(iOS)
        if let namespace {
            matchedTransitionSource(id: id, in: namespace) { $0.clipShape(.rect(cornerRadius: 8)) }
        } else {
            self
        }
        #else
        self
        #endif
    }
}

struct PosterArt: View {
    let item: MediaItem
    let server: ConnectedServer?

    @Environment(\.isCompactWidth) private var compact

    static func aspect(for shape: MediaItem.Shape) -> CGFloat {
        switch shape {
        case .poster: 2 / 3
        case .square: 1
        case .wide: 16 / 9
        }
    }

    private var fetchSize: CGSize {
        let width: CGFloat = compact ? 130 : 200
        return CGSize(width: width, height: width / Self.aspect(for: item.shape))
    }

    var body: some View {
        RemoteImage(value: item.thumb, server: server, size: fetchSize) { loading in
            PosterSkeleton(loading: loading)
        }
        .aspectRatio(Self.aspect(for: item.shape), contentMode: .fit)
        .clipShape(.rect(cornerRadius: 8))
    }
}

private struct PosterSkeleton: View {
    let loading: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if loading, !reduceMotion {
            tile.phaseAnimator([1.0, 0.55]) { view, opacity in
                view.opacity(opacity)
            } animation: { _ in
                .easeInOut(duration: 0.9)
            }
        } else {
            tile
        }
    }

    private var tile: some View {
        Rectangle().fill(.quaternary)
    }
}
