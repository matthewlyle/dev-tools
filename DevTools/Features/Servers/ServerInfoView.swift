import SwiftUI

/// The ⓘ popover beside the server title: host, version, and the connection
/// in use. Reference, so a popover; the column stays for the section list.
struct ServerInfoView: View {
    let entry: ServerStore.Entry

    @Environment(ServerStore.self) private var servers

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                hostMark
                    .frame(width: 16, height: 16)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(entry.resource.hostDescription ?? "Unknown platform")
            }
            if let version = entry.resource.productVersion {
                LabeledContent("Version") {
                    Text(version)
                        .font(.code(.callout))
                        .textSelection(.enabled)
                }
            }
            LabeledContent("Connection") {
                connectionLine
            }
        }
        .frame(minWidth: 280, maxWidth: 420, alignment: .leading)
        .padding()
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
        } else if let probe = servers.activeProbe(for: entry), case .ok(let latency) = probe.outcome {
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(probe.connection.kind.rawValue) · \(latency.milliseconds) ms")
                    .font(.code(.callout))
                Text(probe.connection.uri)
                    .font(.code(.caption))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        } else if !entry.probes.isEmpty {
            Text("Unreachable")
                .foregroundStyle(.red)
        } else {
            Text("Not connected")
                .foregroundStyle(.secondary)
        }
    }
}
