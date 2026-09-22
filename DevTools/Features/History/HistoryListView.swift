import SwiftUI

struct HistoryListView: View {
    let serverID: String

    @Environment(RequestStore.self) private var requests
    @Environment(ServerStore.self) private var servers

    private var connected: ConnectedServer? {
        servers.entry(id: serverID).flatMap { servers.connectedServer(for: $0) }
    }

    @State private var statusFilter: StatusFilter = .any
    @State private var search = ""
    @State private var confirmingClear = false

    private enum StatusFilter: Hashable {
        case any
        case code(Int)
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

    private var scoped: [HistoryEntry] {
        requests.history.filter { $0.serverID == serverID }
    }

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

    private enum Sort: String, CaseIterable, Identifiable {
        case newest = "Newest First"
        case oldest = "Oldest First"
        case status = "Status"
        case slowest = "Slowest First"

        var id: String { rawValue }

        func areInIncreasingOrder(_ a: HistoryEntry, _ b: HistoryEntry) -> Bool {
            switch self {
            case .newest: a.date > b.date
            case .oldest: a.date < b.date
            case .status: a.sortStatus != b.sortStatus ? a.sortStatus < b.sortStatus : a.date > b.date
            case .slowest: a.sortDuration != b.sortDuration ? a.sortDuration > b.sortDuration : a.date > b.date
            }
        }
    }

    @State private var sort: Sort = .newest
    @State private var selection: HistoryEntry.ID?

    private var rows: [HistoryEntry] { filtered.sorted(by: sort.areInIncreasingOrder) }

    var body: some View {
        List(rows, selection: $selection) { entry in
            HistoryRow(entry: entry)
                .tag(entry.id)
                .listRowSeparator(.hidden)
                .contextMenu {
                    Button("Delete", role: .destructive) { delete(entry.id) }
                }
        }
        .sectionListStyle()
        #if os(macOS)
        .onDeleteCommand {
            if let selection { delete(selection) }
        }
        #endif
        .onChange(of: selection) { _, id in
            guard let entry = rows.first(where: { $0.id == id }), let connected else { return }
            requests.replay(entry, on: connected)
        }
        .onAppear {
            if selection == nil { selection = rows.first?.id }
        }
        .sectionListSearch(text: $search, prompt: "Filter history")
        .sectionListToolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Sort By", selection: $sort) {
                        ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.inline)
                    Picker("Status", selection: $statusFilter) {
                        Text(StatusFilter.any.label).tag(StatusFilter.any)
                        ForEach(statusOptions, id: \.self) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("Sort and Filter", systemImage: statusFilter == .any ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
                .help("Sort order and status filter")
            }
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    confirmingClear = true
                } label: {
                    Label(isFiltered ? "Clear Shown" : "Clear History", systemImage: "trash")
                }
                .disabled(filtered.isEmpty)
            }
        }
        .focusedSceneValue(\.clearHistory, filtered.isEmpty ? nil : ClearHistoryAction(serverID: serverID) { confirmingClear = true })
        .focusedSceneValue(\.deleteHistoryEntry, selection.map { id in DeleteHistoryEntryAction(id: id) { delete(id) } })
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

    /// Removes one entry. If it was the one being shown, the workspace is
    /// cleared rather than left displaying a response that no longer has a row.
    private func delete(_ id: HistoryEntry.ID) {
        let wasShowing = selection == id
        requests.deleteHistoryEntry(id)
        if wasShowing {
            selection = nil
            requests.reset()
        }
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry

    @Environment(RequestStore.self) private var requests
    @Environment(ServerStore.self) private var servers

    private var summary: String {
        requests.redactedSummary(of: entry.request, token: servers.entry(id: entry.serverID)?.resource.accessToken)
    }

    private var detail: String {
        var parts: [String] = []
        if let ms = entry.durationMilliseconds { parts.append("\(ms) ms") }
        if let error = entry.error { parts.append(error) }
        parts.append(entry.date.formatted(.relative(presentation: .named)))
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(entry.status.map(String.init) ?? "ERR")
                .font(.code(.callout, weight: .semibold))
                .foregroundStyle(entry.succeeded ? .green : .red)
                .frame(width: 36, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary)
                    .font(.code(.callout))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .help(entry.date.formatted(date: .abbreviated, time: .standard))
    }
}
