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
    @State private var showAdd = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isCompactWidth) private var compact

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items) { item in
                let bound = binding(for: item)
                Group {
                    // A compact width can't fit a name and a value beside the
                    // switch, so the value takes a line of its own.
                    if compact {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                enabledToggle(bound)
                                nameField(item, bound)
                                valuesMenu(item, bound)
                                removeButton(item)
                            }
                            valueField(bound)
                        }
                    } else {
                        HStack(spacing: 8) {
                            enabledToggle(bound)
                            nameField(item, bound)
                            valueField(bound)
                            valuesMenu(item, bound)
                            removeButton(item)
                        }
                    }
                }
                .autocorrectionDisabled()
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 6)), removal: .opacity))
            }

            if suggestions.isEmpty {
                Button {
                    edit { items.append(makeItem("", "")) }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            } else {
                Button {
                    showAdd = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .popover(isPresented: $showAdd, arrowEdge: .bottom) {
                    ParameterAddList(parameters: unused) { parameter in
                        edit { items.append(makeItem(parameter.name, parameter.suggestedValue)) }
                        showAdd = false
                    } onCustom: {
                        edit { items.append(makeItem("", "")) }
                        showAdd = false
                    }
                }
            }
        }
    }

    private func enabledToggle(_ bound: Binding<Item>) -> some View {
        Toggle("Enabled", isOn: bound.enabled)
            .labelsHidden()
    }

    @ViewBuilder
    private func nameField(_ item: Item, _ bound: Binding<Item>) -> some View {
        if let description = description(for: item.name) {
            Text(item.name)
                .font(.code(.body))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 5))
                .frame(minWidth: 120, idealWidth: 180, maxWidth: compact ? .infinity : 260, alignment: .leading)
                .help(description)
        } else {
            TextField(namePlaceholder, text: bound.name)
                .textFieldStyle(.roundedBorder)
                .font(.code(.body))
                .frame(minWidth: 120, idealWidth: 180, maxWidth: compact ? .infinity : 260)
        }
    }

    private func valueField(_ bound: Binding<Item>) -> some View {
        TextField(valuePlaceholder, text: bound.value)
            .textFieldStyle(.roundedBorder)
            .font(.code(.body))
    }

    @ViewBuilder
    private func valuesMenu(_ item: Item, _ bound: Binding<Item>) -> some View {
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
    }

    private func removeButton(_ item: Item) -> some View {
        Button {
            edit { items.removeAll { $0.id == item.id } }
        } label: {
            Label("Remove", systemImage: "minus.circle")
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .help("Remove")
    }

    /// Animates only the user's own adds and removes. `requests.reset()`
    /// empties `items` on a section or server switch, which must not play
    /// as a cascade of removals — so no animation keyed to the array, and
    /// none attached to the row transition, which would run on reset too.
    private func edit(_ change: () -> Void) {
        withAnimation(reduceMotion ? nil : .snappy, change)
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

}

/// The Add-parameter popover: documented parameters with their descriptions
/// as subtitles (a plain `Menu` forces one line and drops them), plus a
/// Custom entry. Tapping one adds it and closes.
private struct ParameterAddList: View {
    let parameters: [SpecParameter]
    let onPick: (SpecParameter) -> Void
    let onCustom: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                row {
                    Label("Custom Parameter", systemImage: "plus")
                        .font(.callout)
                } action: {
                    onCustom()
                }

                if !parameters.isEmpty {
                    Divider().padding(.horizontal, 12)
                    ForEach(parameters) { parameter in
                        row {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(parameter.name)
                                        .font(.code(.callout))
                                    if let type = parameter.type {
                                        Text(type)
                                            .font(.code(.caption2))
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(.quaternary, in: .capsule)
                                    }
                                    if parameter.required {
                                        Text("required")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                    }
                                }
                                if let description = parameter.description, !description.isEmpty {
                                    Text(description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                        } action: {
                            onPick(parameter)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(width: 360)
        .frame(maxHeight: 400)
    }

    @ViewBuilder
    private func row<Label: View>(@ViewBuilder label: () -> Label, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
