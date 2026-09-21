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
    @Environment(\.dismiss) private var dismiss

    @State private var values: [String: String] = [:]
    @State private var options: [String: [RequestStore.PlaceholderOption]] = [:]
    @State private var loading: Set<String> = []
    @State private var datePickerFor: String?

    /// Placeholders the spec describes as epoch seconds.
    private static let epochPlaceholders: Set<String> = ["updatedAt", "timestamp"]

    private var listable: [String] {
        operation.placeholders.filter { RequestStore.listablePlaceholders.contains($0) }
    }

    private var canOpen: Bool {
        operation.placeholders.allSatisfy { !(values[$0] ?? "").isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(operation.summary)
                    .font(.headline)
                Text(operation.template)
                    .font(.code(.callout))
                    .foregroundStyle(.secondary)
            }

            Form {
                ForEach(operation.placeholders, id: \.self) { name in
                    row(for: name)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            if let description = operation.pathParameters.compactMap(\.description).first {
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack {
                if !loading.isEmpty {
                    ProgressView().controlSize(.small)
                        .help("Fetching values from the server")
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Open") {
                    if let server {
                        for name in operation.placeholders {
                            if let value = values[name], !value.isEmpty {
                                memory.remember(placeholder: name, value: value, serverID: server.machineID)
                            }
                        }
                    }
                    open(operation.path(filling: values))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canOpen)
            }
        }
        .padding(20)
        .frame(width: 480)
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
        } else if Self.epochPlaceholders.contains(name) {
            LabeledContent(name) {
                HStack(spacing: 6) {
                    TextField(name, text: binding(name), prompt: Text("epoch seconds"))
                        .labelsHidden()
                        .font(.code(.body))
                        .autocorrectionDisabled()
                    Button {
                        values[name] = String(Int(Date.now.timeIntervalSince1970))
                    } label: {
                        Label("Use Current Time", systemImage: "clock")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .help("Now, as epoch seconds")
                    Button {
                        datePickerFor = name
                    } label: {
                        Label("Pick Date", systemImage: "calendar")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .help("Choose a date and time")
                    .popover(isPresented: Binding(
                        get: { datePickerFor == name },
                        set: { if !$0 { datePickerFor = nil } }
                    )) {
                        DatePicker("Date", selection: dateBinding(name), displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                            .padding()
                    }
                    recentMenu(for: name)
                }
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

    /// Epoch seconds ⇄ Date; an empty or unparseable field reads as now.
    private func dateBinding(_ name: String) -> Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: Double(values[name] ?? "") ?? Date.now.timeIntervalSince1970) },
            set: { values[name] = String(Int($0.timeIntervalSince1970)) }
        )
    }

    private func prompt(for name: String) -> String {
        operation.pathParameters.first { $0.name == name }?.example ?? ""
    }
}
