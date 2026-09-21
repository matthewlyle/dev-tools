import SwiftUI

/// Connection status, transport, and type filters for the notification feed.
struct ActivityControlsView: View {
    @Environment(ActivityStore.self) private var activity
    @Environment(ServerStore.self) private var servers
    @Environment(\.openWindow) private var openWindow

    /// Shown in the standalone window, where there's no main window to open.
    var showsOpenWindow = true

    /// The picker's value: an explicit choice, else whatever is connected,
    /// else the sidebar's server as a sensible first default.
    private var targetID: String? {
        activity.targetServerID ?? activity.server?.machineID ?? servers.selectedID
    }

    private var targetServer: ConnectedServer? {
        targetID.flatMap(servers.entry(id:)).flatMap(servers.connectedServer(for:))
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
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .help("Messages received on the wire since connecting")
                        }
                    }
                    if let error = activity.lastError, activity.status != .failed(error) {
                        Text("Last error: \(error)")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Picker("Server", selection: Binding(
                        get: { targetID },
                        set: { activity.targetServerID = $0 }
                    )) {
                        ForEach(servers.sortedEntries) { entry in
                            Text(entry.resource.name)
                                .tag(String?.some(entry.id))
                        }
                    }
                    .disabled(activity.status.isActive)

                    Picker("Transport", selection: $activity.transport) {
                        ForEach(ActivityTransport.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .disabled(activity.status.isActive)

                    HStack {
                        if activity.status.isActive {
                            Button("Disconnect", role: .destructive) { activity.disconnect() }
                        } else {
                            Button("Connect") {
                                guard let targetServer else { return }
                                activity.connect(to: targetServer)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(targetServer == nil)
                        }
                        Spacer()
                        Button {
                            activity.isPaused.toggle()
                        } label: {
                            Label(activity.isPaused ? "Resume" : "Pause", systemImage: activity.isPaused ? "play.fill" : "pause.fill")
                        }
                        .help(activity.isPaused ? "Resume and show \(activity.pausedCount) held events" : "Freeze the list; the connection stays open")
                        Button {
                            activity.clear()
                        } label: {
                            Label("Clear", systemImage: "trash")
                        }
                        .disabled(activity.events.isEmpty)
                    }
                    .controlSize(.small)

                    if activity.isPaused, activity.pausedCount > 0 {
                        Text("\(activity.pausedCount) events held while paused")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.vertical, 4)
            }

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
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
        }
        .listStyle(.inset)
        .navigationTitle("Activity")
        .toolbar {
            if showsOpenWindow {
                ToolbarItem {
                    Button {
                        openWindow(id: "activity")
                    } label: {
                        Label("Open in New Window", systemImage: "macwindow.on.rectangle")
                    }
                }
            }
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

/// A coloured capsule for an event type; hue is a stable hash of the name.
struct EventTypeBadge: View {
    let type: String

    var body: some View {
        Text(type)
            .font(.caption2.weight(.semibold).monospaced())
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
        return Color(hue: Double(hash % 360) / 360, saturation: 0.55, brightness: 0.85)
    }
}
