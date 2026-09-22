import SwiftUI

protocol KeyValueItem: Identifiable, Hashable {
    var name: String { get set }
    var value: String { get set }
    var enabled: Bool { get set }
}

extension QueryParam: KeyValueItem {}
extension HeaderField: KeyValueItem {}

struct KeyValueEditor<Item: KeyValueItem>: View {
    @Binding var items: [Item]
    let namePlaceholder: String
    let valuePlaceholder: String
    var suggestions: [SpecParameter] = []
    let makeItem: (_ name: String, _ value: String) -> Item

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items) { item in
                let bound = binding(for: item)
                HStack(spacing: 8) {
                    Toggle("Enabled", isOn: bound.enabled)
                        .platformCheckboxToggleStyle()
                        .labelsHidden()
                    if let description = description(for: item.name) {
                        Text(item.name)
                            .font(.code(.body))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 5))
                            .frame(minWidth: 120, idealWidth: 180, maxWidth: 260, alignment: .leading)
                            .help(description)
                    } else {
                        TextField(namePlaceholder, text: bound.name)
                            .textFieldStyle(.roundedBorder)
                            .font(.code(.body))
                            .frame(minWidth: 120, idealWidth: 180, maxWidth: 260)
                    }
                    TextField(valuePlaceholder, text: bound.value)
                        .textFieldStyle(.roundedBorder)
                        .font(.code(.body))
                    if let values = enumValues(for: item.name) {
                        Menu {
                            ForEach(values, id: \.self) { value in
                                Button(value) { bound.wrappedValue.value = value }
                            }
                        } label: {
                            Label("Documented Values", systemImage: "list.bullet")
                                .labelStyle(.iconOnly)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("Documented values")
                    }
                    Button {
                        items.removeAll { $0.id == item.id }
                    } label: {
                        Label("Remove", systemImage: "minus.circle")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .help("Remove")
                }
                .autocorrectionDisabled()
            }

            if suggestions.isEmpty {
                Button {
                    items.append(makeItem("", ""))
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            } else {
                Menu {
                    Button("Custom…") { items.append(makeItem("", "")) }
                    Divider()
                    ForEach(unused) { parameter in
                        Button {
                            items.append(makeItem(parameter.name, parameter.suggestedValue))
                        } label: {
                            Text(menuTitle(parameter))
                        }
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .controlSize(.small)
                .fixedSize()
            }
        }
    }

    /// Looked up by id on every access rather than captured by index:
    /// `requests.reset()` empties the array while UIKit-backed controls
    /// (the switch, the text fields) can still read their bindings during
    /// the layout pass that removes them, and an index binding traps then.
    private func binding(for item: Item) -> Binding<Item> {
        Binding(
            get: { items.first { $0.id == item.id } ?? item },
            set: { updated in
                guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
                items[index] = updated
            }
        )
    }

    private var unused: [SpecParameter] {
        let present = Set(items.map { $0.name.lowercased() })
        return suggestions.filter { !present.contains($0.name.lowercased()) }
    }

    private func description(for name: String) -> String? {
        guard !name.isEmpty, let parameter = suggestions.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return nil }
        return parameter.description ?? "Documented \(parameter.location.rawValue) parameter"
    }

    private func enumValues(for name: String) -> [String]? {
        let values = suggestions.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.enumValues ?? []
        return values.isEmpty ? nil : values
    }

    private func menuTitle(_ parameter: SpecParameter) -> String {
        guard let description = parameter.description?.split(separator: "\n").first, !description.isEmpty else {
            return parameter.name
        }
        let short = description.count > 70 ? String(description.prefix(67)) + "…" : String(description)
        return "\(parameter.name) — \(short)"
    }
}
