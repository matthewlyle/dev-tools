import SwiftUI

/// Everything you do with one server: its endpoint catalog, its request
/// history, its live activity feed. Switching section keeps the server.
struct ServerDetailView: View {
    let entry: ServerStore.Entry
    @Binding var section: ServerSection

    @Environment(ServerStore.self) private var servers

    private var connected: ConnectedServer? { servers.connectedServer(for: entry) }

    var body: some View {
        VStack(spacing: 0) {
            // The window title already names the server; this line is what
            // it runs on. The glyph carries the host in tooltip and VoiceOver.
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: entry.resource.hostSymbol)
                        .foregroundStyle(.secondary)
                        .help(entry.resource.hostDescription ?? "Unknown platform")
                        .accessibilityLabel(entry.resource.hostDescription ?? "Unknown platform")
                    if let version = entry.resource.productVersion {
                        Text("v\(version)")
                            .font(.code(.callout))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    if entry.resource.owned {
                        Text("Owned")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.tint.opacity(0.15), in: .capsule)
                            .foregroundStyle(.tint)
                    }
                }
                connectionLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            switch section {
            case .endpoints:
                EndpointListView(server: connected)
            case .history:
                HistoryListView(serverID: entry.id)
            case .activity:
                ActivityControlsView()
            }
        }
        .navigationTitle(entry.resource.name)
        .toolbar {
            // SwiftUI toolbars have no column alignment on macOS, so this
            // follows Finder/Xcode: view switcher leading after the title,
            // filters and search trailing. Each section adds its own filter.
            // Probe Connections is rare enough to live only in the Server menu.
            ToolbarItem(placement: .navigation) {
                Picker("Section", selection: $section) {
                    ForEach(ServerSection.allCases) { section in
                        Text(section.rawValue).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
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
                .font(.code(.caption))
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
