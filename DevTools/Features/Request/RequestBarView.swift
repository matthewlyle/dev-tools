import SwiftUI

struct RequestBarView: View {
    let server: ConnectedServer?

    @Environment(RequestStore.self) private var requests
    @Environment(SpecStore.self) private var spec
    @Environment(SavedStore.self) private var saved
    @FocusState private var pathFocused: Bool
    @State private var showParameters = false
    @State private var showDocs = false
    @State private var showSave = false

    private var operation: SpecOperation? {
        spec.operation(matching: requests.current.path)
    }

    /// Names seen in the last response, for the include/exclude menus.
    private var shape: ResponseShape? {
        requests.document?.tree.map(ResponseShape.init(root:))
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

                if let operation {
                    Button {
                        showDocs.toggle()
                    } label: {
                        Label("Documentation", systemImage: "info.circle")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .help(operation.summary)
                    .popover(isPresented: $showDocs, arrowEdge: .bottom) {
                        OperationDocs(operation: operation)
                    }
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
                .disabled(server == nil || requests.isSending)
            }

            DisclosureGroup(isExpanded: $showParameters) {
                VStack(alignment: .leading, spacing: 8) {
                    KeyValueEditor(
                        items: $requests.current.query,
                        namePlaceholder: "name",
                        valuePlaceholder: "value",
                        suggestions: operation?.queryParameters ?? []
                    ) { name, value in
                        QueryParam(name: name, value: value)
                    }
                    if let shape, !shape.isEmpty {
                        ResponseShapeRow(shape: shape)
                    }
                }
                .padding(.top, 6)
            } label: {
                sectionLabel("Parameters", count: requests.current.query.filter(\.enabled).count)
            }

            HStack(spacing: 8) {
                Text(requests.previewURL(for: server))
                    .font(.code(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
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
        .onChange(of: requests.parametersRevealToken) { _, _ in
            showParameters = true
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
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.tint.opacity(0.18), in: .capsule)
                    .foregroundStyle(.tint)
            }
        }
        .font(.callout)
    }

    private func send() {
        guard let server else { return }
        requests.send(to: server)
    }

    /// The URL never contains the token (it's sent as a header), so this is
    /// safe to paste anywhere.
    private func copyURL() {
        guard let server, let url = requests.current.url(base: server.baseURL) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    private func copyCurl() {
        guard let server, let command = requests.curl(for: server) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }
}

/// Four pull-downs — include/exclude fields and elements — listing the names
/// the last response actually contained. Picking one appends to that param's
/// comma list, so it shows up as an ordinary row in the editor above.
private struct ResponseShapeRow: View {
    let shape: ResponseShape

    @Environment(RequestStore.self) private var requests

    var body: some View {
        HStack(spacing: 8) {
            Text("Shape")
                .foregroundStyle(.secondary)
                .help("Plex trims the response to the fields and elements you name: includeFields=title,year or excludeElements=Media.")
            menu("includeFields", names: shape.fields)
            menu("excludeFields", names: shape.fields)
            menu("includeElements", names: shape.elements)
            menu("excludeElements", names: shape.elements)
            Spacer(minLength: 0)
        }
        .font(.caption)
        .controlSize(.small)
    }

    @ViewBuilder
    private func menu(_ parameter: String, names: [String]) -> some View {
        let chosen = requests.listParameterValues(parameter)
        if !names.isEmpty {
            Menu {
                ForEach(names, id: \.self) { name in
                    Button {
                        requests.appendToListParameter(parameter, value: name)
                    } label: {
                        if chosen.contains(name) {
                            Label(name, systemImage: "checkmark")
                        } else {
                            Text(name)
                        }
                    }
                    .disabled(chosen.contains(name))
                }
            } label: {
                Text(chosen.isEmpty ? parameter : "\(parameter) (\(chosen.count))")
                    .font(.code(.caption))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
}

private struct OperationDocs: View {
    let operation: SpecOperation

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(operation.summary)
                    .font(.headline)
                Text(operation.template)
                    .font(.code(.callout))
                    .foregroundStyle(.secondary)
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
                                        .font(.caption2)
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
                if let url = operation.docsURL {
                    Link(destination: url) {
                        Label("Open in Developer Docs", systemImage: "arrow.up.right.square")
                    }
                    .font(.callout)
                }
            }
            .padding(16)
        }
        .frame(width: 520)
        .frame(maxHeight: 480)
    }
}
