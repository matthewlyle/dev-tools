import SwiftUI

struct ActivityControlsView: View {
    @Environment(ActivityStore.self) private var activity
    @Environment(ServerStore.self) private var servers

    private var selectedServer: ConnectedServer? {
        servers.selected.flatMap { servers.connectedServer(for: $0) }
    }

    var body: some View {
        @Bindable var activity = activity

        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                        Text(statusText)
                            .font(.callout)
                        Spacer()
                        if activity.status.isActive {
                            Text("\(activity.receivedCount.formatted()) received")
                                .font(.code(.caption))
                                .foregroundStyle(.secondary)
                                .help("Messages received on the wire since connecting")
                        }
                    }
                    if let error = activity.lastError, activity.status != .failed(error) {
                        Text("Last error: \(error)")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    HStack {
                        if activity.status.isActive {
                            Button("Disconnect", role: .destructive) { activity.disconnect() }
                        } else {
                            Button("Connect") {
                                guard let selectedServer else { return }
                                activity.connect(to: selectedServer)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(selectedServer == nil)
                        }
                        Spacer()
                        if !activity.events.isEmpty {
                            Button {
                                activity.clear()
                            } label: {
                                Label("Clear", systemImage: "trash")
                            }
                        }
                    }
                    .controlSize(.small)
                }
                .padding(.vertical, 4)
            }

            if !activity.typeCounts.isEmpty || activity.status.isActive {
                Section("Event Types") {
                    if activity.typeCounts.isEmpty {
                        Text("No events yet")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(activity.typeCounts.sorted { $0.key < $1.key }, id: \.key) { type, count in
                            Toggle(isOn: Binding(
                                get: { !activity.hiddenTypes.contains(type) },
                                set: { _ in activity.toggle(type: type) }
                            )) {
                                HStack {
                                    EventTypeBadge(type: type)
                                    Spacer()
                                    Text(count.formatted())
                                        .font(.code(.caption))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
        .onChange(of: servers.selectedID) { _, id in
            guard let connected = activity.server, connected.machineID != id else { return }
            activity.disconnect()
            activity.clear()
        }
    }

    private var statusText: String {
        switch activity.status {
        case .disconnected: "Disconnected"
        case .connecting: "Connecting to \(activity.server?.name ?? "server")…"
        case .connected: "Connected to \(activity.server?.name ?? "server")"
        case .reconnecting(let attempt, let delay): "Reconnecting (attempt \(attempt), in \(delay)s)…"
        case .failed(let message): "Failed: \(message)"
        }
    }

    private var statusColor: Color {
        switch activity.status {
        case .connected: .green
        case .connecting, .reconnecting: .orange
        case .failed: .red
        case .disconnected: .gray
        }
    }
}

struct EventTypeBadge: View {
    let type: String

    private static let palette: [Color] = [
        .red, .orange, .yellow, .green, .mint, .teal, .cyan, .blue, .indigo, .purple, .pink, .brown,
    ]

    var body: some View {
        Text(type)
            .font(.code(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.18), in: .capsule)
            .foregroundStyle(color)
    }

    private var color: Color {
        var hash: UInt32 = 2_166_136_261
        for byte in type.utf8 {
            hash = (hash ^ UInt32(byte)) &* 16_777_619
        }
        return Self.palette[Int(hash % UInt32(Self.palette.count))]
    }
}
