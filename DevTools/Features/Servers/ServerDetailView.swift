import SwiftUI

struct ServerDetailView: View {
    let entry: ServerStore.Entry

    @Environment(ServerStore.self) private var servers
    @Environment(RequestStore.self) private var requests
    @Environment(SpecStore.self) private var spec

    private var connected: ConnectedServer? { servers.connectedServer(for: entry) }

    /// Tags whose placeholder-free GET operations are worth one click from
    /// the server page. Everything else lives in the Endpoints catalog.
    private static let commonTags: Set<String> = [
        "General", "Library", "Hubs", "Status", "Playlist", "Activities", "Butler", "Preferences", "Updater", "Provider",
    ]

    private var common: [SpecOperation] {
        (spec.catalog?.operations ?? []).filter {
            Self.commonTags.contains($0.tag) && $0.placeholders.isEmpty && !$0.template.contains(":/transcode")
        }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(entry.resource.name)
                            .font(.title3.weight(.semibold))
                        if entry.resource.owned {
                            Text("Owned")
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.tint.opacity(0.15), in: .capsule)
                                .foregroundStyle(.tint)
                        }
                    }
                    Text(headerSubtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    connectionLine
                }
                .padding(.vertical, 4)
            }

            Section("Common Requests") {
                ForEach(common) { operation in
                    Button {
                        guard let connected else { return }
                        requests.open(operation, path: operation.template, on: connected)
                    } label: {
                        Text(operation.template)
                            .font(.callout.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(connected == nil)
                    .help(operation.description ?? operation.summary)
                }
            }
        }
        .listStyle(.inset)
        .navigationTitle(entry.resource.name)
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await servers.probe(id: entry.id) }
                } label: {
                    Label("Probe Connections", systemImage: "dot.radiowaves.left.and.right")
                }
                .disabled(entry.isProbing)
            }
        }
    }

    private var headerSubtitle: String {
        [entry.resource.product, entry.resource.productVersion, entry.resource.platform]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    @ViewBuilder
    private var connectionLine: some View {
        if entry.isProbing {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Probing connections…")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if let probe = servers.activeProbe(for: entry), case .ok(let latency) = probe.outcome {
            Text("\(probe.connection.kind.rawValue) · \(probe.connection.uri) · \(latency.milliseconds) ms")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        } else if !entry.probes.isEmpty {
            Text("Unreachable")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
}
