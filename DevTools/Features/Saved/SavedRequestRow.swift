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

/// Saves the request in the workspace: a new saved request, or, while it
/// was loaded from one, an update with Save as New beside it.
private struct SaveCurrentRequestSheet: View {
    let server: ConnectedServer

    @Environment(RequestStore.self) private var requests
    @Environment(SavedStore.self) private var saved
    @Environment(SpecStore.self) private var spec

    var body: some View {
        let summary = requests.redactedSummary(of: requests.current, token: server.accessToken)
        if let editing = requests.editingSavedID.flatMap({ id in saved.saved.first { $0.id == id } }) {
            SaveRequestSheet(
                title: "Update Request",
                name: editing.name,
                summary: summary,
                action: "Update",
                secondary: ("Save as New", { name in
                    saved.add(name: name, request: requests.current, serverID: server.machineID)
                })
            ) { name in
                saved.update(id: editing.id, name: name, request: requests.current)
            }
        } else {
            SaveRequestSheet(
                title: "Save Request",
                name: spec.operation(matching: requests.current.path)?.summary ?? requests.current.path,
                summary: summary,
                action: "Save"
            ) { name in
                saved.add(name: name, request: requests.current, serverID: server.machineID)
            }
        }
    }
}

/// Presents `SaveCurrentRequestSheet` from a request bar, and on Save
/// Request… (⌘S). Only the visible section's bar answers the command: on a
/// compact width every tab keeps its pushed bar alive.
private struct SavesCurrentRequest: ViewModifier {
    @Binding var isPresented: Bool
    let server: ConnectedServer?

    @Environment(RequestStore.self) private var requests
    @Environment(\.sectionIsActive) private var isActive

    func body(content: Content) -> some View {
        content
            .onChange(of: requests.saveRequestToken) { _, _ in
                if isActive, server != nil { isPresented = true }
            }
            .sheet(isPresented: $isPresented) {
                if let server { SaveCurrentRequestSheet(server: server) }
            }
    }
}

extension View {
    func savesCurrentRequest(isPresented: Binding<Bool>, server: ConnectedServer?) -> some View {
        modifier(SavesCurrentRequest(isPresented: isPresented, server: server))
    }
}
