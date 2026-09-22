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

    var body: some View {
        VStack(spacing: 0) {
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
                        Picker("View", selection: $tab) {
                            ForEach(MediaResultsTab.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                        if tab == .response, let document = requests.document {
                            BodyControls(document: document, response: response, collapsed: $collapsed)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
            .background(.fill.quaternary, in: .rect(cornerRadius: 12))
            .padding(12)

            if let response = requests.response {
                Group {
                    switch tab {
                    case .posters:
                        if requests.document == nil {
                            ProgressView()
                        } else if items.isEmpty {
                            ContentUnavailableView(
                                "No Items",
                                systemImage: "square.grid.3x3",
                                description: Text("The query matched nothing. Loosen a filter and run it again.")
                            )
                        } else {
                            grid
                        }
                    case .response:
                        if let document = requests.document {
                            RawResponseView(document: document, response: response, collapsed: $collapsed)
                        } else {
                            ProgressView()
                        }
                    case .headers:
                        HeadersView(response: response, server: server, editable: false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = requests.errorMessage {
                ContentUnavailableView(
                    "Request Failed",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "No Results",
                    systemImage: "square.grid.3x3",
                    description: Text("Run a query to see its items as posters.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
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
        .focusedSceneValue(
            \.showMediaInfo,
            selectedID == nil ? nil : ShowMediaInfoAction(visible: showInfo) { showInfo.toggle() }
        )
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 130, maximum: 150), spacing: 16, alignment: .top)],
                alignment: .leading,
                spacing: 20
            ) {
                ForEach(items) { item in
                    PosterCell(item: item, server: server, isSelected: item.id == selectedID) {
                        selectedID = item.id
                        showInfo = true
                    }
                }
            }
            .padding(16)
        }
    }
}

private struct PosterCell: View {
    let item: MediaItem
    let server: ConnectedServer?
    let isSelected: Bool
    let select: () -> Void

    private static let width: CGFloat = 130

    private var artSize: CGSize {
        switch item.shape {
        case .poster: CGSize(width: Self.width, height: Self.width * 1.5)
        case .square: CGSize(width: Self.width, height: Self.width)
        case .wide: CGSize(width: Self.width, height: Self.width * 9 / 16)
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
        Button(action: select) {
            VStack(alignment: .leading, spacing: 6) {
                RemoteImage(value: item.thumb, server: server, size: artSize) {
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
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.tint, lineWidth: 3)
                    }
                }

                Text(item.title)
                    .font(.callout)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: Self.width, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(item.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
