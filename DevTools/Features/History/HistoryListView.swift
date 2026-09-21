import SwiftUI

/// Requests sent to one server, newest first, filterable by status.
struct HistoryListView: View {
    let serverID: String

    @Environment(RequestStore.self) private var requests

    @State private var statusFilter: StatusFilter = .any

    private enum StatusFilter: Hashable {
        case any
        case code(Int)
        /// No response at all: transport error, timeout, cancelled.
        case failed

        func matches(_ entry: HistoryEntry) -> Bool {
            switch self {
            case .any: true
            case .code(let code): entry.status == code
            case .failed: entry.status == nil
            }
        }

        var label: String {
            switch self {
            case .any: "Any Status"
            case .code(let code): String(code)
            case .failed: "Failed"
            }
        }
    }

    /// This server's entries, before the status filter.
    private var scoped: [HistoryEntry] {
        requests.history.filter { $0.serverID == serverID }
    }

    /// Status codes that appear in this server's history, ascending, then Failed if any.
    private var statusOptions: [StatusFilter] {
        var codes = Set<Int>()
        var anyFailed = false
        for entry in scoped {
            if let status = entry.status { codes.insert(status) } else { anyFailed = true }
        }
        var options = codes.sorted().map(StatusFilter.code)
        if anyFailed { options.append(.failed) }
        return options
    }

    private var isFiltered: Bool { statusFilter != .any }

    private var filtered: [HistoryEntry] {
        isFiltered ? scoped.filter(statusFilter.matches) : scoped
    }

    var body: some View {
        List(filtered) { entry in
            Button {
                requests.load(entry)
            } label: {
                HistoryRow(entry: entry)
            }
            .buttonStyle(.plain)
        }
        .listStyle(.inset)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 8) {
                Picker("Status", selection: $statusFilter) {
                    Text(StatusFilter.any.label).tag(StatusFilter.any)
                    ForEach(statusOptions, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 120)
                Spacer()
                Button(role: .destructive) {
                    let shown = Set(filtered.map(\.id))
                    requests.clearHistory { shown.contains($0.id) }
                } label: {
                    Label(isFiltered ? "Clear Shown" : "Clear", systemImage: "trash")
                }
                .disabled(filtered.isEmpty)
            }
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .overlay {
            if filtered.isEmpty {
                ContentUnavailableView(
                    "No History",
                    systemImage: "clock",
                    description: Text(isFiltered ? "No requests with this status." : "Requests you send to this server show up here.")
                )
            }
        }
        .onChange(of: statusOptions) { _, options in
            if statusFilter != .any, !options.contains(statusFilter) {
                statusFilter = .any
            }
        }
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry

    @Environment(RequestStore.self) private var requests
    @Environment(ServerStore.self) private var servers

    /// Path + params with any token masked: the server's own token wherever
    /// it appears, plus `X-Plex-Token=…` pairs typed into the path.
    private var summary: String {
        guard requests.redactToken else { return entry.request.summary }
        var text = requests.redacted(entry.request.summary, token: servers.entry(id: entry.serverID)?.resource.accessToken)
        text = text.replacing(/X-Plex-Token=[^&\s]+/) { _ in "X-Plex-Token=\(RequestStore.mask)" }
        return text
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(entry.status.map(String.init) ?? "ERR")
                .font(.caption.weight(.semibold).monospaced())
                .foregroundStyle(entry.succeeded ? .green : .red)
                .frame(width: 32, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(summary)
                    .font(.callout.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
    }

    private var subtitle: String {
        var parts = [entry.serverName]
        if let ms = entry.durationMilliseconds { parts.append("\(ms) ms") }
        if let error = entry.error { parts.append(error) }
        parts.append(entry.date.formatted(.relative(presentation: .named)))
        return parts.joined(separator: " · ")
    }
}
