import SwiftUI

/// Fills an operation's `{placeholders}` before opening it. A placeholder
/// gets the richest helper its value allows: a picker when the spec enumerates
/// it or the server can list it (libraries, playlists, collections, tuner
/// devices), a now/date helper for epoch seconds, and otherwise a field with
/// values seen in earlier responses. Whatever you pick is remembered.
struct PlaceholderSheet: View {
    let operation: SpecOperation
    let server: ConnectedServer?
    var prefilled: [String: String] = [:]
    let open: (String) -> Void

    @Environment(RequestStore.self) private var requests
    @Environment(ValueMemory.self) private var memory

    @State private var values: [String: String] = [:]
    @State private var options: [String: [RequestStore.PlaceholderOption]] = [:]
    @State private var loading: Set<String> = []

    private var listable: [String] {
        operation.placeholders.filter { RequestStore.listablePlaceholders.contains($0) }
    }

    private var canOpen: Bool {
        operation.placeholders.allSatisfy { !(values[$0] ?? "").isEmpty }
    }

    var body: some View {
        SheetScaffold(
            title: operation.summary,
            width: 480,
            confirm: SheetAction(title: "Open", disabled: !canOpen, run: commit),
            busy: !loading.isEmpty
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text(operation.template)
                    .font(.code(.callout))
                    .foregroundStyle(.secondary)
                if let description = operation.description, !description.isEmpty {
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                OperationAccessLabel(access: operation.access)
            }
        } content: {
            Form {
                ForEach(operation.placeholders, id: \.self) { name in
                    Section {
                        row(for: name)
                    } footer: {
                        if let description = operation.pathParameters.first(where: { $0.name == name })?.description {
                            Text(description)
                        }
                    }
                }
                if !operation.queryParameters.isEmpty {
                    Section {
                        ForEach(operation.queryParameters) { ParameterDocRow(parameter: $0) }
                    } header: {
                        Text("Query Parameters")
                    } footer: {
                        if operation.supportsMediaQuery {
                            Text(OperationDocs.mediaQueryNote)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .onAppear {
            for name in operation.placeholders {
                values[name] = prefilled[name]
                    ?? server.flatMap { memory.lastUsed(placeholder: name, serverID: $0.machineID) }
                    ?? ""
            }
            if let server {
                for name in listable { options[name] = requests.options(for: name, server: server) }
            }
        }
        .task {
            guard let server else { return }
            for name in listable where options[name, default: []].isEmpty {
                loading.insert(name)
                await requests.preloadOptions(for: name, on: server, force: true)
                options[name] = requests.options(for: name, server: server)
                loading.remove(name)
            }
            for name in listable {
                if let only = options[name], only.count == 1, values[name, default: ""].isEmpty {
                    values[name] = only[0].key
                }
            }
        }
    }

    private func commit() {
        if let server {
            for name in operation.placeholders {
                if let value = values[name], !value.isEmpty {
                    memory.remember(placeholder: name, value: value, serverID: server.machineID)
                }
            }
        }
        open(operation.path(filling: values))
    }

    @ViewBuilder
    private func row(for name: String) -> some View {
        let enumValues = operation.pathParameters.first { $0.name == name }?.enumValues ?? []
        let listed = options[name] ?? []

        if !enumValues.isEmpty {
            Picker(name, selection: binding(name)) {
                Text("Choose…").tag("")
                ForEach(enumValues, id: \.self) { value in
                    Text(value).tag(value)
                }
            }
        } else if !listed.isEmpty {
            Picker(name, selection: binding(name)) {
                Text("Choose…").tag("")
                if listed.contains(where: { $0.group != nil }) {
                    let groups = Dictionary(grouping: listed) { $0.group ?? "" }
                    ForEach(groups.keys.sorted(), id: \.self) { group in
                        Section(group) {
                            ForEach(groups[group] ?? []) { option in
                                Text("\(option.title) (\(option.key))").tag(option.key)
                            }
                        }
                    }
                } else {
                    ForEach(listed) { option in
                        Text("\(option.title) (\(option.key))").tag(option.key)
                    }
                }
            }
        } else if EpochDate.isEpochName(name) {
            LabeledContent {
                HStack(spacing: 6) {
                    TextField(name, text: binding(name), prompt: Text("epoch seconds"))
                        .labelsHidden()
                        .font(.code(.body))
                        .autocorrectionDisabled()
                    EpochDateButton(value: binding(name))
                    recentMenu(for: name)
                }
            } label: {
                Text(name)
                EpochReadout(value: values[name] ?? "")
            }
        } else {
            LabeledContent(name) {
                HStack(spacing: 6) {
                    TextField(name, text: binding(name), prompt: Text(prompt(for: name)))
                        .labelsHidden()
                        .font(.code(.body))
                        .autocorrectionDisabled()
                    recentMenu(for: name)
                }
            }
        }
    }

    /// Values seen in earlier responses that fit `name`, grouped by where
    /// they came from. Hidden when nothing fits.
    @ViewBuilder
    private func recentMenu(for name: String) -> some View {
        let candidates = Array((server.map { memory.candidates(for: name, serverID: $0.machineID) } ?? []).prefix(24))
        if !candidates.isEmpty {
            let groups = Dictionary(grouping: candidates) { "\($0.element).\($0.attribute)" }
            Menu {
                ForEach(groups.keys.sorted(), id: \.self) { source in
                    Section(source) {
                        ForEach(groups[source] ?? []) { seen in
                            Button(seen.title == seen.value ? seen.value : "\(seen.title)  (\(seen.value))") {
                                values[name] = seen.value
                            }
                        }
                    }
                }
            } label: {
                Label("Recently Seen", systemImage: "clock.arrow.circlepath")
                    .labelStyle(.iconOnly)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Values from responses you've already received")
        }
    }

    private func binding(_ name: String) -> Binding<String> {
        Binding(
            get: { values[name] ?? "" },
            set: { values[name] = $0 }
        )
    }

    private func prompt(for name: String) -> String {
        operation.pathParameters.first { $0.name == name }?.example ?? ""
    }
}
