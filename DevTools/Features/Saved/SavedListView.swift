import SwiftUI

/// Requests kept on purpose for one server. Selecting one loads it into
/// the request bar; nothing is sent until you press Send.
struct SavedListView: View {
    let serverID: String

    @Environment(SavedStore.self) private var saved
    @Environment(RequestStore.self) private var requests
    @Environment(ServerStore.self) private var servers

    @State private var search = ""
    @State private var selection: SavedRequest.ID?
    @State private var editing: SavedRequest?
    @State private var deleting: SavedRequest?

    private var token: String? { servers.entry(id: serverID)?.resource.accessToken }

    private var rows: [SavedRequest] {
        let needle = search.trimmingCharacters(in: .whitespaces)
        let all = saved.items(for: serverID)
        guard !needle.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(needle)
                || $0.request.summary.localizedCaseInsensitiveContains(needle)
                || $0.notes.localizedCaseInsensitiveContains(needle)
        }
    }

    var body: some View {
        List(rows, selection: $selection) { item in
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .lineLimit(1)
                Text(requests.redactedSummary(of: item.request, token: token))
                    .font(.code(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.vertical, 2)
            .help(item.notes.isEmpty ? item.request.summary : item.notes)
            .tag(item.id)
            .contextMenu {
                Button("Rename…") { editing = item }
                Divider()
                Button("Delete…", role: .destructive) { deleting = item }
            }
        }
        .listStyle(.inset)
        .onChange(of: selection) { _, id in
            guard let item = rows.first(where: { $0.id == id }) else { return }
            requests.load(item.request)
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Filter saved")
        .overlay {
            if rows.isEmpty {
                ContentUnavailableView(
                    "No Saved Requests",
                    systemImage: "bookmark",
                    description: Text(search.isEmpty ? "Build a request and press ⌘S to keep it here." : "No saved requests match the filter.")
                )
            }
        }
        .sheet(item: $editing) { item in
            SaveRequestSheet(title: "Rename Request", name: item.name, notes: item.notes, action: "Save") { name, notes in
                saved.update(id: item.id, name: name, notes: notes)
            }
        }
        .confirmationDialog(
            "Delete “\(deleting?.name ?? "")”?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting
        ) { item in
            Button("Delete", role: .destructive) { saved.remove(id: item.id) }
        } message: { _ in
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
