import SwiftUI

struct RequestBarView: View {
    let server: ConnectedServer?

    @Environment(RequestStore.self) private var requests
    @Environment(SpecStore.self) private var spec
    @FocusState private var pathFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isCompactWidth) private var compact

    @State private var showSave = false
    @State private var focusID = UUID()

    private var operation: SpecOperation? {
        spec.operation(matching: requests.current.path)
    }

    var body: some View {
        @Bindable var requests = requests

        VStack(alignment: .leading, spacing: 10) {
            // The bar scrolls away with the response, so a compact width
            // spends height rather than squeezing the path: it takes the
            // whole first line, the URL wraps, and Send closes the bar.
            if compact {
                HStack(spacing: 8) {
                    methodBadge
                    pathField
                }
            } else {
                HStack(spacing: 8) {
                    methodBadge
                    pathField
                    sendButton
                }
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

            if compact {
                urlPreview
                HStack(spacing: 8) {
                    HistoryNavButtons(server: server)
                    Spacer(minLength: 0)
                    sendButton
                }
            } else {
                HStack(spacing: 8) {
                    HistoryNavButtons(server: server)
                    urlPreview
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(12)
        .task(id: requests.pathFocusPending) {
            guard requests.pathFocusPending else { return }
            requests.pathFocusPending = false
            pathFocused = true
        }
        // A compact width hands the screen to the response: the keyboard
        // would cover it the moment it arrives.
        .task {
            if requests.pathFocusHolder != nil, !compact { pathFocused = true }
        }
        .onChange(of: pathFocused) { _, focused in
            if focused {
                requests.pathFocusHolder = focusID
            } else if requests.pathFocusHolder == focusID {
                requests.pathFocusHolder = nil
            }
        }
        .savesCurrentRequest(isPresented: $showSave, server: server)
    }

    private var methodBadge: some View {
        Text("GET")
            .font(.code(.caption, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.quaternary, in: .rect(cornerRadius: 5))
    }

    private var pathField: some View {
        @Bindable var requests = requests
        return TextField("/library/sections", text: $requests.current.path)
            .textFieldStyle(.roundedBorder)
            .font(.code(.body))
            .focused($pathFocused)
            .onSubmit(send)
            .autocorrectionDisabled()
    }

    private var sendButton: some View {
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

    private var urlPreview: some View {
        Text(requests.previewURL(for: server))
            .font(.code(.caption))
            .foregroundStyle(.secondary)
            .lineLimit(compact ? 3 : 1)
            .truncationMode(.middle)
            .textSelection(.enabled)
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
}

/// The request's documentation: a size-capped popover from the toolbar's ⓘ,
/// or on a compact width the sheet that popover becomes, which it fills.
struct OperationDocs: View {
    let operation: SpecOperation

    @Environment(\.isCompactWidth) private var compact

    var body: some View {
        if compact {
            docs
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        } else {
            docs
                .frame(maxWidth: 440)
                .frame(maxHeight: 480)
        }
    }

    private var docs: some View {
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
                    parameters
                }
                if operation.supportsMediaQuery {
                    Text("Accepts media queries: field operators (`year>>=2000`), `sort=`, `group=`, `limit=`, and `push=1`/`pop=1`/`or=1` for grouping.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let url = operation.docsURL {
                    Link(destination: url) {
                        Label("Open in Developer Docs", systemImage: "safari")
                    }
                    .font(.callout)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(compact ? 20 : 16)
        }
    }

    /// Name beside description where there's width for both; on a compact
    /// width the name column would break names mid-word, so each parameter
    /// stacks its name over its description.
    @ViewBuilder
    private var parameters: some View {
        if compact {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(operation.parameters) { parameter in
                    VStack(alignment: .leading, spacing: 3) {
                        name(parameter)
                        description(parameter)
                    }
                }
            }
        } else {
            Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 6) {
                ForEach(operation.parameters) { parameter in
                    GridRow {
                        name(parameter)
                        description(parameter)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func name(_ parameter: SpecParameter) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(parameter.name)
                .font(.code(.callout))
            Text(parameter.location.rawValue + (parameter.type.map { " · \($0)" } ?? ""))
                .font(.code(.caption2))
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func description(_ parameter: SpecParameter) -> some View {
        if let text = parameter.description, !text.isEmpty {
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
