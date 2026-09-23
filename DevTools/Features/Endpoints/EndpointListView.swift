import SwiftUI

/// Every documented GET operation, grouped by tag, with the requests saved
/// for this server pinned as the first group. One list, one filter.
struct EndpointListView: View {
    let server: ConnectedServer?
    let serverID: String

    @Environment(SpecStore.self) private var spec
    @Environment(RequestStore.self) private var requests
    @Environment(SavedStore.self) private var saved
    @Environment(\.showSectionDetail) private var showDetail

    @State private var search = ""
    @State private var pending: SpecOperation?

    private var needle: String { search.trimmingCharacters(in: .whitespaces) }

    private var groups: [SpecCatalog.TagGroup] {
        spec.catalog?.groups(matching: search) ?? []
    }

    private var savedRows: [SavedRequest] {
        let all = saved.items(for: serverID)
        guard !needle.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(needle)
                || $0.request.summary.localizedCaseInsensitiveContains(needle)
        }
    }

    var body: some View {
        list.listFilter(text: $search, prompt: "Filter endpoints")
    }

    private var list: some View {
        SectionColumnList {
            if !savedRows.isEmpty {
                Section {
                    ForEach(savedRows) { item in
                        SavedRequestRow(item: item, serverID: serverID, disabled: server == nil)
                            .sectionColumnRow()
                    }
                } header: {
                    SectionColumnHeader(title: "Saved")
                }
            }
            ForEach(groups) { group in
                Section {
                    ForEach(group.operations) { operation in
                        EndpointRow(operation: operation, disabled: server == nil, shared: server?.owned == false) {
                            open(operation)
                        }
                        .sectionColumnRow()
                    }
                } header: {
                    SectionColumnHeader(title: group.name)
                }
            }
        }
        .overlay {
            if spec.catalog == nil {
                if let message = spec.errorMessage {
                    ContentUnavailableView("Spec Unavailable", systemImage: "doc.questionmark", description: Text(message))
                } else {
                    ProgressView()
                }
            } else if groups.isEmpty && savedRows.isEmpty {
                ZeroState(text: "No endpoints match the filter.")
            }
        }
        .sheet(item: $pending) { operation in
            PlaceholderSheet(operation: operation, server: server) { path in
                guard let server else { return }
                requests.open(operation, path: path, on: server)
                showDetail?()
            }
        }
    }

    private func open(_ operation: SpecOperation) {
        guard let server else { return }
        if operation.placeholders.isEmpty {
            requests.open(operation, path: operation.template, on: server)
            showDetail?()
        } else {
            pending = operation
        }
    }
}

/// One catalog row. On a server you don't own, admin-only operations carry a
/// lock and are dimmed with the reason, but stay clickable — seeing the 403 is
/// part of exploring the API.
private struct EndpointRow: View {
    let operation: SpecOperation
    let disabled: Bool
    let shared: Bool
    let action: () -> Void

    private var lockedOut: Bool { shared && operation.access == .admin }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(operation.template)
                        .font(.code(.codeListRow))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if lockedOut {
                        Image(systemName: "lock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Admin only")
                    }
                    if operation.supportsMediaQuery {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help("Supports media queries")
                            .accessibilityLabel("Supports media queries")
                    }
                }
                Text(operation.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .contentShape(.rect)
            .opacity(lockedOut ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(lockedOut
            ? "Admin only. This server is shared with you, so it will answer 403."
            : (operation.access == .admin ? "Admin only. " : "") + (operation.description ?? operation.summary))
        .contextMenu {
            if let url = operation.docsURL {
                Link("Open in Developer Docs", destination: url)
            }
        }
    }
}
