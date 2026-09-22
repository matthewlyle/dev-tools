import SwiftUI

struct ServerDetailView: View {
    let entry: ServerStore.Entry
    @Binding var section: ServerSection

    @Environment(ServerStore.self) private var servers

    private var connected: ConnectedServer? { servers.connectedServer(for: entry) }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    hostMark
                        .frame(width: 16, height: 16)
                        .foregroundStyle(.secondary)
                        .help(entry.resource.hostDescription ?? "Unknown platform")
                        .accessibilityLabel(entry.resource.hostDescription ?? "Unknown platform")
                    if let version = entry.resource.productVersion {
                        Text("v\(version)")
                            .font(.code(.callout))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
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
                EndpointListView(server: connected, serverID: entry.id)
            case .history:
                HistoryListView(serverID: entry.id)
            case .activity:
                ActivityControlsView()
            case .mediaQuery:
                MediaQueryBuilderView(server: connected)
            }
        }
        .navigationTitle(entry.resource.name)
        .toolbar {
            ToolbarItem(placement: .platformSectionSwitcher) {
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
    private var hostMark: some View {
        switch entry.resource.hostMark {
        case .symbol(let name):
            Image(systemName: name)
                .resizable()
                .scaledToFit()
        case .asset(let name):
            Image(name)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
        }
    }

    @ViewBuilder
    private var connectionLine: some View {
        if entry.isProbing {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Connecting…")
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
