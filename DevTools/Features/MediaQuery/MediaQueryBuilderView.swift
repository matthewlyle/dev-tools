import SwiftUI

/// Builds a media query visually and runs it against
/// `/library/sections/{id}/all`; the result lands in the read-only workspace.
///
/// Pickers bind straight to the model and every one always has a tag for its
/// current value; dependent resets happen in `onChange`, after the update.
/// A picker whose selection has no tag, or whose setter rewrites the model,
/// makes SwiftUI re-assert the selection every render and the view hangs.
struct MediaQueryBuilderView: View {
    let server: ConnectedServer?

    @Environment(MediaQueryStore.self) private var store
    @Environment(RequestStore.self) private var requests

    @State private var sectionsChecked = false

    private var sections: [RequestStore.SectionOption] {
        server.map { requests.sections(for: $0) } ?? []
    }

    private var canRun: Bool {
        server != nil && store.currentType != nil && !requests.isSending
    }

    var body: some View {
        @Bindable var store = store

        Group {
            if server == nil {
                ContentUnavailableView(
                    "Not Connected",
                    systemImage: "server.rack",
                    description: Text("Connect to this server to build a query.")
                )
            } else if sections.isEmpty {
                if sectionsChecked {
                    ContentUnavailableView(
                        "No Libraries",
                        systemImage: "books.vertical",
                        description: Text("This server has no library sections to query.")
                    )
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                Form {
                    Section {
                        Picker("Library", selection: $store.query.sectionKey) {
                            if !sections.contains(where: { $0.key == store.query.sectionKey }) {
                                Text("Choose…").tag(store.query.sectionKey)
                            }
                            ForEach(sections) { section in
                                Text(section.title).tag(section.key)
                            }
                        }

                        if let details = store.currentDetails {
                            Picker("Type", selection: $store.query.type) {
                                if store.currentType == nil {
                                    Text("Choose…").tag(store.query.type)
                                }
                                ForEach(details.types) { type in
                                    Text(type.title).tag(type.number)
                                }
                            }
                        } else if store.isLoading {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Fetching this library's fields")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if let error = store.errorMessage {
                            Text(error)
                                .font(.callout)
                                .foregroundStyle(.red)
                        }
                    }

                    if let type = store.currentType {
                        Section {
                            ForEach(store.query.terms) { term in
                                TermRow(term: termBinding(term), type: type, server: server) {
                                    store.query.terms.removeAll { $0.id == term.id }
                                }
                            }
                            Button {
                                if let field = type.fields.first {
                                    store.query.terms.append(MediaQuery.Term(field: field))
                                }
                            } label: {
                                Label("Add Filter", systemImage: "plus")
                            }
                            .disabled(type.fields.isEmpty)
                            if store.query.terms.count > 1 {
                                Toggle("Match any filter", isOn: $store.query.matchAny)
                                    .platformCheckboxToggleStyle()
                                    .help("Join filters with OR instead of AND")
                            }
                        } header: {
                            Text("Filters")
                        }

                        Section {
                            ForEach(store.query.sorts) { sort in
                                SortRow(sort: sortBinding(sort), options: type.sorts) {
                                    store.query.sorts.removeAll { $0.id == sort.id }
                                }
                            }
                            Button {
                                if let option = type.sorts.first {
                                    store.query.sorts.append(MediaQuery.Sort(key: option.key))
                                }
                            } label: {
                                Label("Add Sort", systemImage: "plus")
                            }
                            .disabled(type.sorts.isEmpty)
                        } header: {
                            Text("Sort")
                        }

                        Section {
                            Picker("Group By", selection: $store.query.group) {
                                Text("None").tag("")
                                ForEach(type.fields) { field in
                                    Text(field.title).tag(field.key)
                                }
                            }
                            TextField("Limit", text: $store.query.limit, prompt: Text("all"))
                                .font(.code(.body))
                        } header: {
                            Text("Options")
                        }

                        Section {
                            Text(store.query.request().summary)
                                .font(.code(.caption))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button {
                                run()
                            } label: {
                                Label("Run Query", systemImage: "play.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!canRun)
                            .keyboardShortcut(.defaultAction)
                        } header: {
                            Text("Query")
                        }
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
            }
        }
        .task(id: server?.machineID) {
            sectionsChecked = false
            if let server {
                store.serverChanged(to: server.machineID)
                await requests.preloadSections(on: server)
                if !store.query.hasSection, let first = requests.sections(for: server).first {
                    store.query.sectionKey = first.key
                }
            }
            sectionsChecked = true
        }
        .onChange(of: store.query.sectionKey) { _, _ in
            store.sectionChanged()
        }
        .onChange(of: store.query.type) { _, _ in
            store.typeChanged()
        }
        .task(id: store.query.sectionKey) {
            guard let server, store.query.hasSection else { return }
            await store.loadDetails(section: store.query.sectionKey, on: server)
        }
        .focusedSceneValue(
            \.runMediaQuery,
            canRun ? RunMediaQueryAction(summary: store.query.request().summary, run: run) : nil
        )
    }

    private func run() {
        guard let server, store.currentType != nil else { return }
        requests.load(store.query.request())
        requests.send(to: server)
    }

    /// Bindings keyed by id, not index: when a row removes its element the
    /// others keep pointing at their own, the removed row reads its last
    /// snapshot, and writes to a gone element are dropped. Index-backed
    /// `ForEach($array)` bindings shift on removal and hang the view.
    private func termBinding(_ term: MediaQuery.Term) -> Binding<MediaQuery.Term> {
        Binding(
            get: { store.query.terms.first { $0.id == term.id } ?? term },
            set: { updated in
                if let index = store.query.terms.firstIndex(where: { $0.id == term.id }) {
                    store.query.terms[index] = updated
                }
            }
        )
    }

    private func sortBinding(_ sort: MediaQuery.Sort) -> Binding<MediaQuery.Sort> {
        Binding(
            get: { store.query.sorts.first { $0.id == sort.id } ?? sort },
            set: { updated in
                if let index = store.query.sorts.firstIndex(where: { $0.id == sort.id }) {
                    store.query.sorts[index] = updated
                }
            }
        )
    }
}

private struct TermRow: View {
    @Binding var term: MediaQuery.Term
    let type: MediaType
    let server: ConnectedServer?
    let remove: () -> Void

    private var fields: [MediaField] { type.fields }
    private var operators: [MediaOperator] { term.fieldType.operators }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Picker("Field", selection: $term.field) {
                    if !fields.contains(where: { $0.key == term.field }) {
                        Text(term.field).tag(term.field)
                    }
                    ForEach(fields) { field in
                        Text(field.title).tag(field.key)
                    }
                }
                .labelsHidden()

                Picker("Operator", selection: $term.operatorKey) {
                    if !operators.contains(where: { $0.key == term.operatorKey }) {
                        Text(term.operatorKey).tag(term.operatorKey)
                    }
                    ForEach(operators) { op in
                        Text(op.title).tag(op.key)
                    }
                }
                .labelsHidden()

                Spacer(minLength: 0)

                Button(role: .destructive, action: remove) {
                    Label("Remove Filter", systemImage: "minus.circle")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Remove this filter")
            }

            if term.fieldType == .boolean {
                Picker("Value", selection: $term.value) {
                    if term.value != "1", term.value != "0" {
                        Text("true").tag(term.value)
                    }
                    Text("true").tag("1")
                    Text("false").tag("0")
                }
                .labelsHidden()
            } else if let filter = type.filter(for: term.field) {
                FilterValueField(term: $term, filter: filter, server: server)
            } else {
                TextField("Value", text: $term.value, prompt: Text(term.fieldType.valuePrompt))
                    .labelsHidden()
                    .font(.code(.body))
                    .autocorrectionDisabled()
            }
        }
        .padding(.vertical, 2)
        .onChange(of: term.field) { _, key in
            guard let field = fields.first(where: { $0.key == key }) else { return }
            term.fieldType = field.type
            term.operatorKey = field.type.operators.first?.key ?? "="
            term.value = field.type == .boolean ? "1" : ""
            term.label = ""
        }
    }
}

/// A value editor backed by the server's list of possible values for the
/// field. Few values → a menu. Many → a typeahead over their titles. Tag
/// fields store the picked id and show its name; fields whose values are
/// their own titles accept typed text directly.
private struct FilterValueField: View {
    @Binding var term: MediaQuery.Term
    let filter: MediaFilter
    let server: ConnectedServer?

    @Environment(MediaQueryStore.self) private var store
    @State private var search = ""
    @FocusState private var focused: Bool

    private static let menuLimit = 40
    private static let suggestionLimit = 12

    private var values: [MediaFilterValue]? { store.values(for: filter) }
    private var typedIsValue: Bool { MediaFilterValue.keysAreValues(values ?? []) }

    private var matches: [MediaFilterValue] {
        guard let values else { return [] }
        let needle = search.trimmingCharacters(in: .whitespaces)
        let hits = needle.isEmpty ? values : values.filter { $0.title.localizedCaseInsensitiveContains(needle) }
        return Array(hits.prefix(Self.suggestionLimit))
    }

    var body: some View {
        Group {
            if let values, !values.isEmpty, values.count <= Self.menuLimit {
                Picker("Value", selection: $term.value) {
                    Text("Choose…").tag("")
                    if !term.value.isEmpty, !values.contains(where: { $0.key == term.value }) {
                        Text(term.label.isEmpty ? term.value : term.label).tag(term.value)
                    }
                    ForEach(values) { value in
                        Text(value.title).tag(value.key)
                    }
                }
                .labelsHidden()
                .onChange(of: term.value) { _, key in
                    term.label = values.first { $0.key == key }?.title ?? ""
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        TextField("Value", text: $search, prompt: Text(prompt))
                            .labelsHidden()
                            .font(.code(.body))
                            .autocorrectionDisabled()
                            .focused($focused)
                            .onSubmit {
                                if !typedIsValue, let first = matches.first { pick(first) }
                            }
                            .onChange(of: search) { _, text in
                                if typedIsValue {
                                    term.value = text
                                    term.label = ""
                                } else if text != term.label {
                                    term.value = ""
                                    term.label = ""
                                }
                            }
                        if store.isLoadingValues(for: filter) {
                            ProgressView().controlSize(.small)
                                .help("Fetching possible values")
                        }
                    }

                    // Inline, not a popover: a popover takes key-window focus,
                    // and the field re-selects its text when focus returns.
                    if showSuggestions {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(matches) { value in
                                Button {
                                    pick(value)
                                } label: {
                                    HStack {
                                        Text(value.title)
                                        if value.key != value.title {
                                            Spacer()
                                            Text(value.key)
                                                .font(.code(.caption))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 6))
                    }
                }
            }
        }
        .onAppear { search = term.label.isEmpty ? term.value : term.label }
        .task(id: "\(server?.machineID ?? "")/\(filter.valuesKey)") {
            guard let server else { return }
            await store.loadValues(for: filter, on: server)
        }
    }

    private var prompt: String {
        if values == nil { return "text" }
        return typedIsValue ? "text, or type to search" : "type to search"
    }

    /// Suggestions show while the field is focused and holds a search that
    /// isn't already the picked value's name.
    private var showSuggestions: Bool {
        focused && !search.isEmpty && search != term.label && !matches.isEmpty
    }

    private func pick(_ value: MediaFilterValue) {
        term.value = value.key
        term.label = value.title
        search = value.title
    }
}

private struct SortRow: View {
    @Binding var sort: MediaQuery.Sort
    let options: [MediaSortField]
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Picker("Sort By", selection: $sort.key) {
                if !options.contains(where: { $0.key == sort.key }) {
                    Text(sort.key).tag(sort.key)
                }
                ForEach(options) { option in
                    Text(option.title).tag(option.key)
                }
            }
            .labelsHidden()

            Picker("Direction", selection: $sort.descending) {
                Text("Ascending").tag(false)
                Text("Descending").tag(true)
            }
            .labelsHidden()

            Spacer(minLength: 0)

            Button(role: .destructive, action: remove) {
                Label("Remove Sort", systemImage: "minus.circle")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("Remove this sort")
        }
    }
}
