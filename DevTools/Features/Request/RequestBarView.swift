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
                KeyValueEditor(
                    items: $requests.current.query,
                    namePlaceholder: "name",
                    valuePlaceholder: "value",
                    suggestions: operation?.queryParameters ?? []
                ) { name, value in
                    QueryParam(name: name, value: value)
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
                    Label("Save Request", systemImage: "bookmark")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .disabled(server == nil)
                .help("Save this request (⌘S)")
                Button(action: copyURL) {
                    Label("Copy URL", systemImage: "doc.on.doc")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .disabled(server == nil)
                .help("Copy URL (token masked)")
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
            SaveRequestSheet(
                title: "Save Request",
                name: operation?.summary ?? requests.current.path,
                notes: "",
                action: "Save"
            ) { name, notes in
                guard let server else { return }
                saved.add(name: name, notes: notes, request: requests.current, serverID: server.machineID)
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
            }
            .padding(16)
        }
        .frame(width: 520)
        .frame(maxHeight: 480)
    }
}
