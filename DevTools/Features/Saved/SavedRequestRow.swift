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
        .help(item.notes.isEmpty ? item.request.summary : item.notes)
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
            SaveRequestSheet(title: "Rename Request", name: item.name, notes: item.notes, action: "Save") { name, notes in
                saved.update(id: item.id, name: name, notes: notes)
            }
        }
        .confirmationDialog("Delete “\(item.name)”?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { saved.remove(id: item.id) }
        } message: {
            Text("This can't be undone.")
        }
    }
}

/// Name and notes for a saved request — new, renamed, or updated. Shows the
/// request being kept so you can see what you're saving, not just its title.
struct SaveRequestSheet: View {
    let title: String
    @State var name: String
    @State var notes: String
    /// Path + params being saved; nil when only renaming.
    var summary: String? = nil
    let action: String
    /// An alternative commit, e.g. "Save as New" beside "Update".
    var secondary: (title: String, commit: (_ name: String, _ notes: String) -> Void)? = nil
    let commit: (_ name: String, _ notes: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var trimmedNotes: String { notes.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                if let summary {
                    Text(summary)
                        .font(.code(.callout))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }

            Form {
                TextField("Name", text: $name)
                    .focused($nameFocused)
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(2...5)
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if let secondary {
                    Button(secondary.title) {
                        secondary.commit(trimmedName, trimmedNotes)
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty)
                }
                Button(action) {
                    commit(trimmedName, trimmedNotes)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(trimmedName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear { nameFocused = true }
    }
}
