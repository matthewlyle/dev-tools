import SwiftUI

/// Fills an operation's `{placeholders}` before opening it. Sections come
/// from the server; everything else offers values seen in earlier responses
/// and remembers what you last used.
struct PlaceholderSheet: View {
    let operation: SpecOperation
    let server: ConnectedServer?
    var prefilled: [String: String] = [:]
    let open: (String) -> Void

    @Environment(RequestStore.self) private var requests
    @Environment(ValueMemory.self) private var memory
    @Environment(\.dismiss) private var dismiss

    @State private var values: [String: String] = [:]
    @State private var sections: [RequestStore.SectionOption] = []
    @State private var loadingSections = false

    private var needsSections: Bool { operation.placeholders.contains("sectionId") }

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
                    if name == "sectionId", !sections.isEmpty {
                        Picker(name, selection: binding(name)) {
                            Text("Choose…").tag("")
                            ForEach(sections) { section in
                                Text("\(section.title) (\(section.key))").tag(section.key)
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
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            if let description = operation.pathParameters.compactMap(\.description).first {
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack {
                if loadingSections {
                    ProgressView().controlSize(.small)
                        .help("Fetching this server's libraries")
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
        }
        .task {
            guard needsSections, let server else { return }
            loadingSections = true
            sections = await requests.fetchSections(on: server)
            loadingSections = false
            if sections.count == 1, values["sectionId", default: ""].isEmpty {
                values["sectionId"] = sections[0].key
            }
        }
    }

    /// Values seen in earlier responses that plausibly fit `name`.
    @ViewBuilder
    private func recentMenu(for name: String) -> some View {
        let candidates = server.map { memory.candidates(for: name, serverID: $0.machineID) } ?? []
        if !candidates.isEmpty {
            Menu {
                ForEach(candidates.prefix(30)) { seen in
                    Button {
                        values[name] = seen.value
                    } label: {
                        Text("\(seen.title)  ·  \(seen.element).\(seen.attribute) = \(seen.value)")
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
        operation.pathParameters.first { $0.name == name }?.example ?? name
    }
}
