import SwiftUI

struct HeadersView<Header: View>: View {
    let response: PlexResponse?
    let server: ConnectedServer?
    var editable: Bool = true
    @ViewBuilder let header: () -> Header

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

        ScrollView {
            header()
            VStack(alignment: .leading, spacing: 10) {
                Text("Request")
                    .font(.headline)

                if editable {
                    KeyValueEditor(
                        items: $requests.current.headers,
                        namePlaceholder: "Header-Name",
                        valuePlaceholder: "value",
                        suggestions: spec.catalog?.documentedHeaders ?? []
                    ) { name, value in
                        HeaderField(name: name, value: value)
                    }
                } else {
                    let sent = requests.current.headers.filter(\.enabled)
                    if sent.isEmpty {
                        Text("No custom headers")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                            ForEach(sent, id: \.name) { header in
                                GridRow {
                                    Text(header.name)
                                        .foregroundStyle(.secondary)
                                    Text(header.value)
                                        .font(.code(.caption))
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
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

            if responseRows.isEmpty {
                if response != nil {
                    Text("No headers")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                }
            } else {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    ForEach(responseRows) { row in
                        GridRow(alignment: .firstTextBaseline) {
                            Text(row.name)
                                .font(.code(.codeDetailRow))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .gridColumnAlignment(.leading)
                            Text(row.value)
                                .font(.code(.codeDetailRow))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
    }
}
