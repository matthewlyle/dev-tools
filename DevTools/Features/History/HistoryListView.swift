import SwiftUI

/// Requests sent to one server, newest first, filterable by status.
struct HistoryListView: View {
    let serverID: String

    @Environment(RequestStore.self) private var requests

    @State private var statusFilter: StatusFilter = .any
    @State private var search = ""
    @State private var confirmingClear = false

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

    private var isFiltered: Bool { statusFilter != .any || !needle.isEmpty }

    private var needle: String { search.trimmingCharacters(in: .whitespaces) }

    private var filtered: [HistoryEntry] {
        scoped.filter { entry in
            statusFilter.matches(entry)
                && (needle.isEmpty || entry.request.summary.localizedCaseInsensitiveContains(needle))
        }
    }

    @State private var sortOrder = [KeyPathComparator(\HistoryEntry.date, order: .reverse)]
    @State private var selection: HistoryEntry.ID?

    private var rows: [HistoryEntry] { filtered.sorted(using: sortOrder) }

    var body: some View {
        // A multicolumn table, as the HIG expects for attribute data on the
        // Mac: sortable by clicking a heading, resizable, alternating rows.
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Status", value: \.sortStatus) { entry in
                Text(entry.status.map(String.init) ?? "ERR")
                    .font(.code(.callout, weight: .semibold))
                    .foregroundStyle(entry.succeeded ? .green : .red)
                    .help(entry.error ?? "")
            }
            .width(min: 52, ideal: 60, max: 80)

            TableColumn("Path", value: \.request.summary) { entry in
                HistoryPathCell(entry: entry)
            }

            TableColumn("Duration", value: \.sortDuration) { entry in
                Text(entry.durationMilliseconds.map { "\($0) ms" } ?? "—")
                    .font(.code(.callout))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .width(min: 56, ideal: 66, max: 90)

            TableColumn("When", value: \.date) { entry in
                Text(entry.date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))
                    .foregroundStyle(.secondary)
                    .help(entry.date.formatted(date: .abbreviated, time: .standard))
            }
            .width(min: 76, ideal: 96, max: 140)
        }
        .alternatingRowBackgrounds()
        .onChange(of: selection) { _, id in
            // Selecting a row loads it into the request bar, like picking a
            // message in Mail; nothing is sent until you press Send.
            guard let entry = rows.first(where: { $0.id == id }) else { return }
            requests.load(entry)
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Filter history")
        .toolbar {
            ToolbarItem {
                Picker("Status", selection: $statusFilter) {
                    Text(StatusFilter.any.label).tag(StatusFilter.any)
                    ForEach(statusOptions, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }
                .help("Show only requests with this status")
            }
            ToolbarItem {
                Button(role: .destructive) {
                    confirmingClear = true
                } label: {
                    Label(isFiltered ? "Clear Shown" : "Clear History", systemImage: "trash")
                }
                .disabled(filtered.isEmpty)
            }
        }
        .focusedSceneValue(\.clearHistory, filtered.isEmpty ? nil : ClearHistoryAction(serverID: serverID) { confirmingClear = true })
        .confirmationDialog(
            isFiltered ? "Clear the \(filtered.count) shown requests?" : "Clear all history for this server?",
            isPresented: $confirmingClear,
            titleVisibility: .visible
        ) {
            Button(isFiltered ? "Clear Shown" : "Clear History", role: .destructive) {
                let shown = Set(filtered.map(\.id))
                requests.clearHistory { shown.contains($0.id) }
            }
        } message: {
            Text("This can't be undone.")
        }
        .overlay {
            if filtered.isEmpty {
                ContentUnavailableView(
                    "No History",
                    systemImage: "clock",
                    description: Text(isFiltered ? "No requests match the filter." : "Requests you send to this server show up here.")
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

/// Path + params with any token masked: the server's own token wherever it
/// appears, plus `X-Plex-Token=…` pairs typed into the path.
private struct HistoryPathCell: View {
    let entry: HistoryEntry

    @Environment(RequestStore.self) private var requests
    @Environment(ServerStore.self) private var servers

    private var summary: String {
        guard requests.redactToken else { return entry.request.summary }
        var text = requests.redacted(entry.request.summary, token: servers.entry(id: entry.serverID)?.resource.accessToken)
        text = text.replacing(/X-Plex-Token=[^&\s]+/) { _ in "X-Plex-Token=\(RequestStore.mask)" }
        return text
    }

    var body: some View {
        Text(summary)
            .font(.code(.callout))
            .lineLimit(1)
            .truncationMode(.middle)
            .help(entry.error ?? summary)
    }
}
