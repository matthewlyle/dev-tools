import SwiftUI

/// One saved request in the catalog: name over masked path. Click loads it
/// into the request bar; right-click to rename or delete.
struct SavedRequestRow: View {
    let item: SavedRequest
    let serverID: String
    let disabled: Bool

    @Environment(SavedStore.self) private var saved
    @Environment(RequestStore.self) private var requests
    @Environment(ServerStore.self) private var servers

    @State private var renaming = false
    @State private var deleting = false

    private var token: String? { servers.entry(id: serverID)?.resource.accessToken }

    var body: some View {
        Button {
            requests.load(item.request)
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

/// Name and notes for a saved request — new or renamed.
struct SaveRequestSheet: View {
    let title: String
    @State var name: String
    @State var notes: String
    let action: String
    let commit: (_ name: String, _ notes: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)

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
                Button(action) {
                    commit(trimmedName, notes.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(trimmedName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { nameFocused = true }
    }
}
