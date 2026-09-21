import SwiftUI

/// Collects values for `{placeholder}` segments before opening a templated
/// path. `sectionId` offers the server's libraries as a picker.
struct PlaceholderSheet: View {
    let operation: SpecOperation
    let server: ConnectedServer?
    let open: (String) -> Void

    @Environment(RequestStore.self) private var requests
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
                        TextField(name, text: binding(name), prompt: Text(prompt(for: name)))
                            .font(.code(.body))
                            .autocorrectionDisabled()
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
                    Text("Loading libraries…").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Open") {
                    open(operation.path(filling: values))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canOpen)
            }
        }
        .padding(20)
        .frame(width: 460)
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
