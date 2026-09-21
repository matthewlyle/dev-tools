import SwiftUI

/// Request headers (editable) on top, response headers below.
struct HeadersView: View {
    let response: PlexResponse?
    let server: ConnectedServer?

    @Environment(RequestStore.self) private var requests
    @Environment(SpecStore.self) private var spec
    @State private var showImplicit = false

    private struct Row: Identifiable {
        var id: String { name }
        let name: String
        let value: String
    }

    private var responseRows: [Row] {
        (response?.headers ?? [:])
            .map { Row(name: $0.key, value: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        @Bindable var requests = requests

        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Request")
                        .font(.headline)
                    Spacer()
                    Picker("Token", selection: $requests.current.tokenPlacement) {
                        ForEach(TokenPlacement.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .help("Send X-Plex-Token as a header or a query parameter")
                }

                KeyValueEditor(
                    items: $requests.current.headers,
                    namePlaceholder: "Header-Name",
                    valuePlaceholder: "value",
                    suggestions: spec.catalog?.documentedHeaders ?? []
                ) { name, value in
                    HeaderField(name: name, value: value)
                }

                DisclosureGroup(isExpanded: $showImplicit) {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                        ForEach(requests.implicitHeaders(for: server), id: \.name) { header in
                            GridRow {
                                Text(header.name)
                                    .foregroundStyle(.secondary)
                                Text(header.value)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .font(.code(.caption))
                    .padding(.top, 4)
                } label: {
                    Text("Always sent (\(requests.implicitHeaders(for: server).count))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)

            Divider()

            HStack {
                Text("Response")
                    .font(.headline)
                Spacer()
                if response == nil {
                    Text("No response yet")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Table(responseRows) {
                TableColumn("Header") { row in
                    Text(row.name)
                        .font(.code(.body))
                        .textSelection(.enabled)
                }
                .width(min: 160, ideal: 260)

                TableColumn("Value") { row in
                    Text(row.value)
                        .font(.code(.body))
                        .textSelection(.enabled)
                }
            }
        }
    }
}
