import SwiftUI

/// One saved request in the catalog: name over masked path. Click loads it
/// into the request bar and sends it; right-click to rename or delete.
struct SavedRequestRow: View {
    let item: SavedRequest
    let serverID: String
    let disabled: Bool

    @Environment(SavedStore.self) private var saved
    @Environment(RequestStore.self) private var requests
    @Environment(ServerStore.self) private var servers
    @Environment(\.showSectionDetail) private var showDetail

    @State private var renaming = false
    @State private var deleting = false

    private var token: String? { servers.entry(id: serverID)?.resource.accessToken }

    private var connected: ConnectedServer? {
        servers.entry(id: serverID).flatMap { servers.connectedServer(for: $0) }
    }

    var body: some View {
        Button {
            requests.load(saved: item)
            if let connected { requests.send(to: connected) }
            showDetail?()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "bookmark.fill")
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .lineLimit(1)
                    Text(requests.redactedSummary(of: item.request, token: token))
                        .font(.code(.caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(requests.redactedSummary(of: item.request, token: token))
        .contextMenu {
            Button("Rename…") { renaming = true }
            Divider()
            Button("Delete…", role: .destructive) { deleting = true }
        }
        // Delete asks first, so it isn't the destructive role: that role
        // removes the row as the swipe ends, before the confirmation.
        .swipeActions {
            Button("Delete…") { deleting = true }
                .tint(.red)
            Button("Rename…") { renaming = true }
        }
        .sheet(isPresented: $renaming) {
            SaveRequestSheet(title: "Rename Request", name: item.name, action: "Save") { name in
                saved.update(id: item.id, name: name)
            }
        }
        .confirmationDialog("Delete “\(item.name)”?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { saved.remove(id: item.id) }
        } message: {
            Text("This can't be undone.")
        }
    }
}

/// The name for a saved request — new, renamed, or updated. Shows the
/// request being kept so you can see what you're saving, not just its title.
struct SaveRequestSheet: View {
    let title: String
    @State var name: String
    /// Path + params being saved; nil when only renaming.
    var summary: String? = nil
    let action: String
    /// An alternative commit, e.g. "Save as New" beside "Update".
    var secondary: (title: String, commit: (_ name: String) -> Void)? = nil
    let commit: (_ name: String) -> Void

    @FocusState private var nameFocused: Bool

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        SheetScaffold(
            title: title,
            width: 460,
            confirm: SheetAction(title: action, disabled: trimmedName.isEmpty) { commit(trimmedName) },
            secondary: secondary.map { secondary in
                SheetAction(title: secondary.title, disabled: trimmedName.isEmpty) { secondary.commit(trimmedName) }
            }
        ) {
            if let summary {
                Text(summary)
                    .font(.code(.callout))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        } content: {
            Form {
                TextField("Name", text: $name)
                    .focused($nameFocused)
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .onAppear { nameFocused = true }
    }
}
