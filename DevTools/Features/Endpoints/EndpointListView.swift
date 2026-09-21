import SwiftUI

/// Every documented GET operation, grouped by tag, searchable. Selecting one
/// loads it into the request bar (prompting for path placeholders) and sends.
struct EndpointListView: View {
    let server: ConnectedServer?

    @Environment(SpecStore.self) private var spec
    @Environment(RequestStore.self) private var requests

    @State private var search = ""
    @State private var pending: SpecOperation?

    private var groups: [SpecCatalog.TagGroup] {
        spec.catalog?.groups(matching: search) ?? []
    }

    var body: some View {
        List {
            ForEach(groups) { group in
                Section(group.name) {
                    ForEach(group.operations) { operation in
                        EndpointRow(operation: operation, disabled: server == nil) {
                            open(operation)
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
        .searchable(text: $search, placement: .toolbar, prompt: "Filter endpoints")
        .overlay {
            if spec.catalog == nil {
                if let message = spec.errorMessage {
                    ContentUnavailableView("Spec Unavailable", systemImage: "doc.questionmark", description: Text(message))
                } else {
                    ProgressView()
                }
            } else if groups.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .sheet(item: $pending) { operation in
            PlaceholderSheet(operation: operation, server: server) { path in
                guard let server else { return }
                requests.open(operation, path: path, on: server)
            }
        }
    }

    private func open(_ operation: SpecOperation) {
        guard let server else { return }
        if operation.placeholders.isEmpty {
            requests.open(operation, path: operation.template, on: server)
        } else {
            pending = operation
        }
    }
}

private struct EndpointRow: View {
    let operation: SpecOperation
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(operation.template)
                        .font(.callout.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if operation.supportsMediaQuery {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help("Supports media queries")
                            .accessibilityLabel("Supports media queries")
                    }
                }
                Text(operation.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(operation.description ?? operation.summary)
    }
}
