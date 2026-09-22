import SwiftUI

struct RequestBarView: View {
    let server: ConnectedServer?

    @Environment(RequestStore.self) private var requests
    @Environment(SpecStore.self) private var spec
    @Environment(SavedStore.self) private var saved
    @FocusState private var pathFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    @State private var showSave = false

    private var operation: SpecOperation? {
        spec.operation(matching: requests.current.path)
    }

    /// The saved request the bar was loaded from, while that session lasts.
    private var editingSaved: SavedRequest? {
        requests.editingSavedID.flatMap { id in saved.saved.first { $0.id == id } }
    }

    var body: some View {
        @Bindable var requests = requests

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("GET")
                    .font(.code(.caption, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: .rect(cornerRadius: 5))

                TextField("/library/sections", text: $requests.current.path)
                    .textFieldStyle(.roundedBorder)
                    .font(.code(.body))
                    .focused($pathFocused)
                    .onSubmit(send)
                    .autocorrectionDisabled()

                if operation != nil {
                    Button {
                        requests.showingDocs = true
                    } label: {
                        Label("Documentation", systemImage: "info.circle")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .help(operation?.summary ?? "")
                }

                Button(action: send) {
                    Label {
                        Text("Send")
                    } icon: {
                        if requests.isSending {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                    }
                }
                .buttonStyle(.glassProminent)
                .animation(reduceMotion ? nil : .smooth(duration: 0.15), value: requests.isSending)
                .disabled(server == nil || requests.isSending)
            }

            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("Parameters", count: requests.current.query.filter(\.enabled).count)
                KeyValueEditor(
                    items: $requests.current.query,
                    namePlaceholder: "name",
                    valuePlaceholder: "value",
                    suggestions: operation?.queryParameters ?? []
                ) { name, value in
                    QueryParam(name: name, value: value)
                }
            }

            HStack(spacing: 8) {
                HistoryNavButtons(server: server)
                Text(requests.previewURL(for: server))
                    .font(.code(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
                Button {
                    if let url = operation?.docsURL { openURL(url) }
                } label: {
                    Label("Open in Developer Docs", systemImage: "safari")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .disabled(operation?.docsURL == nil)
                .help(operation.map { "Open “\($0.summary)” on developer.plex.tv" } ?? "No documentation for this path")
                Button {
                    showSave = true
                } label: {
                    Label(editingSaved == nil ? "Save Request" : "Update Saved Request", systemImage: editingSaved == nil ? "bookmark" : "bookmark.fill")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .disabled(server == nil)
                .help(editingSaved.map { "Editing “\($0.name)” — update it or save as new (⌘S)" } ?? "Save this request (⌘S)")
                Menu {
                    Button("Copy as cURL") { copyCurl() }
                } label: {
                    Label("Copy URL", systemImage: "doc.on.doc")
                        .labelStyle(.iconOnly)
                } primaryAction: {
                    copyURL()
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(server == nil)
                .help("Copy URL. Long-press for cURL.")
            }
        }
        .padding(12)
        .onChange(of: requests.pathFocusToken) { _, _ in
            pathFocused = true
        }
        .onChange(of: requests.saveRequestToken) { _, _ in
            if server != nil { showSave = true }
        }
        .sheet(isPresented: $showSave) {
            if let server {
                let summary = requests.redactedSummary(of: requests.current, token: server.accessToken)
                if let editing = editingSaved {
                    SaveRequestSheet(
                        title: "Update Request",
                        name: editing.name,
                        notes: editing.notes,
                        summary: summary,
                        action: "Update",
                        secondary: ("Save as New", { name, notes in
                            saved.add(name: name, notes: notes, request: requests.current, serverID: server.machineID)
                        })
                    ) { name, notes in
                        saved.update(id: editing.id, name: name, notes: notes, request: requests.current)
                    }
                } else {
                    SaveRequestSheet(
                        title: "Save Request",
                        name: operation?.summary ?? requests.current.path,
                        notes: "",
                        summary: summary,
                        action: "Save"
                    ) { name, notes in
                        saved.add(name: name, notes: notes, request: requests.current, serverID: server.machineID)
                    }
                }
            }
        }
    }

    private func sectionLabel(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
            if count > 0 {
                Text(String(count))
                    .contentTransition(.numericText(value: Double(count)))
                    .font(.code(.caption2, weight: .semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.tint.opacity(0.18), in: .capsule)
                    .foregroundStyle(.tint)
            }
        }
        .font(.callout)
        .animation(reduceMotion ? nil : .snappy, value: count)
    }

    private func send() {
        guard let server else { return }
        requests.send(to: server)
    }

    /// The URL never contains the token (it's sent as a header), so this is
    /// safe to paste anywhere.
    private func copyURL() {
        guard let server, let url = requests.current.url(base: server.baseURL) else { return }
        Clipboard.copy(url.absoluteString)
    }

    private func copyCurl() {
        guard let server, let command = requests.curl(for: server) else { return }
        Clipboard.copy(command)
    }
}

struct OperationDocs: View {
    let operation: SpecOperation

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(operation.summary)
                    .font(.headline)
                Text(operation.template)
                    .font(.code(.callout))
                    .foregroundStyle(.secondary)
                switch operation.access {
                case .admin:
                    Label("Requires admin — the server's owner", systemImage: "lock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .open:
                    Label("No token required", systemImage: "lock.open")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .anyUser:
                    EmptyView()
                }
                if let description = operation.description, !description.isEmpty {
                    Text(description)
                        .font(.callout)
                }
                if !operation.parameters.isEmpty {
                    Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 6) {
                        ForEach(operation.parameters) { parameter in
                            GridRow {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(parameter.name)
                                        .font(.code(.callout))
                                    Text(parameter.location.rawValue + (parameter.type.map { " · \($0)" } ?? ""))
                                        .font(.code(.caption2))
                                        .foregroundStyle(.tertiary)
                                }
                                Text(parameter.description ?? "")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                if operation.supportsMediaQuery {
                    Text("Accepts media queries: field operators (`year>>=2000`), `sort=`, `group=`, `limit=`, and `push=1`/`pop=1`/`or=1` for grouping.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
        .frame(maxWidth: 440)
        .frame(maxHeight: 480)
    }
}
