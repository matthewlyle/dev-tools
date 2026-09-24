import SwiftUI

/// Anything that reads the events is its own view, so only it redraws per frame;
/// this body reads nothing but the selection.
struct ActivityEventsView: View {
    @Environment(ActivityStore.self) private var activity
    @Environment(\.sectionIsActive) private var isActive
    @Environment(\.isCompactWidth) private var compact
    @Environment(\.connectionInTabBar) private var connectionInTabBar

    var body: some View {
        Group {
            if compact {
                events.sectionListToolbar(followsList: false) {
                    ToolbarItemGroup(placement: .primaryAction) {
                        ActivityTypeMenu()
                        ClearEventsButton()
                    }
                }
            } else {
                events
            }
        }
        .focusedSceneValue(
            \.showMediaInfo,
            isActive && activity.selectedEvent != nil
                ? ShowMediaInfoAction(visible: true) { activity.selectedEventID = nil }
                : nil
        )
    }

    private var events: some View {
        EventList()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !connectionInTabBar {
                    ActivityConnectionControl()
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .glassEffect(.regular, in: .capsule)
                        .frame(maxWidth: 560)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }
            }
    }
}

struct ActivityToolbarItems: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(id: "activity.clear", placement: .primaryAction) {
            ClearEventsButton()
        }
    }
}

private struct ClearEventsButton: View {
    @Environment(ActivityStore.self) private var activity

    var body: some View {
        Button {
            activity.clear()
        } label: {
            Label("Clear Events", systemImage: "trash")
        }
        .disabled(activity.events.isEmpty)
        .help("Clear events")
    }
}

struct ActivityConnectionControl: View {
    @Environment(ActivityStore.self) private var activity
    @Environment(ServerStore.self) private var servers
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.tabViewBottomAccessoryPlacement) private var accessoryPlacement
    @State private var connections = 0

    private var selectedServer: ConnectedServer? {
        servers.selected.flatMap { servers.connectedServer(for: $0) }
    }

    private var inline: Bool { accessoryPlacement == .inline }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(statusColor)
                    .symbolEffect(.pulse, options: .repeating, isActive: isConnecting && !reduceMotion)
                    .symbolEffect(.bounce, value: connections)
                    .accessibilityHidden(true)
                Text(statusText)
                    .font(.code(.callout))
                    .lineLimit(1)
                    .contentTransition(.numericText())
                if activity.status.isActive, !inline {
                    Text("\(activity.receivedCount.formatted()) received")
                        .font(.code(.caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help("Messages received on the wire since connecting")
                        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 6)), removal: .opacity))
                }
                Spacer(minLength: 8)
                if activity.status.isActive {
                    Button("Disconnect", role: .destructive) { activity.disconnect() }
                        .buttonStyle(.borderless)
                } else {
                    Button("Connect") {
                        guard let selectedServer else { return }
                        activity.connect(to: selectedServer)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedServer == nil)
                }
            }
            .animation(reduceMotion ? nil : .smooth, value: activity.status)
            if accessoryPlacement == nil, let error = activity.lastError, activity.status != .failed(error) {
                Text("Last error: \(error)")
                    .font(.code(.caption))
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .controlSize(.small)
        .onChange(of: activity.status) { _, status in
            if status == .connected, !reduceMotion { connections += 1 }
        }
    }

    private var statusText: String {
        switch activity.status {
        case .disconnected: "Disconnected"
        case .connecting: "Connecting…"
        case .connected: "Connected"
        case .reconnecting(let attempt, let delay): "Reconnecting (attempt \(attempt), in \(delay)s)…"
        case .failed(let message): "Failed: \(message)"
        }
    }

    private var isConnecting: Bool {
        switch activity.status {
        case .connecting, .reconnecting: true
        case .connected, .disconnected, .failed: false
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

private struct EventList: View {
    @Environment(ActivityStore.self) private var activity
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sectionIsActive) private var isActive
    @Environment(\.isCompactWidth) private var compact

    var body: some View {
        let focused = compact ? nil : activity.focusedSession
        let visible = focused.map { session in activity.visibleEvents.filter { $0.session == session } } ?? activity.visibleEvents

        ZStack {
            if activity.events.isEmpty, !activity.status.isActive {
                FillingScrollView {
                    disconnected
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .restingStateTransition(rising: true)
                .zIndex(1)
            } else {
                events(visible)
                    .sectionListStyle()
                    .fadesSignalRings()
                    .overlay {
                        ZStack {
                            if visible.isEmpty, activity.status.isActive {
                                ZeroState(text: "Waiting for events.")
                                    .restingStateTransition(rising: true)
                            }
                        }
                    }
                    .animation(reduceMotion ? nil : .smooth, value: activity.events.first?.id)
                    .transition(.identity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .signalRings(visible: isActive && activity.status == .connected)
        .focusedSceneValue(\.clearEvents, isActive && !activity.events.isEmpty ? ClearEventsAction { activity.clear() } : nil)
    }

    @ViewBuilder
    private func events(_ visible: [NotificationEvent]) -> some View {
        @Bindable var activity = activity
        if compact {
            List(visible) { event in
                Button {
                    activity.selectedEventID = event.id
                } label: {
                    EventRow(event: event, title: activity.title(for: event))
                        .contentShape(.rect)
                }
                .foregroundStyle(.primary)
                .listRowSeparator(.hidden)
                .sectionListRow(selected: event.id == activity.selectedEventID)
            }
        } else {
            List(visible, selection: $activity.selectedEventID) { event in
                EventRow(event: event, title: activity.title(for: event))
                    .tag(event.id)
                    .listRowSeparator(.hidden)
                    .sectionListRow(selected: event.id == activity.selectedEventID)
            }
            .contextMenu(forSelectionType: NotificationEvent.ID.self) { _ in
            } primaryAction: { ids in
                if let id = ids.first { activity.selectedEventID = id }
            }
        }
    }

    @ViewBuilder
    private var disconnected: some View {
        if case .failed(let message) = activity.status {
            ContentUnavailableView(
                "Couldn't Connect",
                systemImage: "exclamationmark.triangle",
                description: Text("\(message) Check that the server is reachable, then connect again.")
            )
        } else {
            ZeroState(text: "Connect to see events here.")
        }
    }
}

private struct EventRow: View {
    let event: NotificationEvent
    let title: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isCompactWidth) private var compact

    var body: some View {
        Group {
            if compact {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        EventTypeBadge(type: event.type)
                            .fixedSize()
                        Spacer(minLength: 8)
                        time
                    }
                    subject
                        .lineLimit(2)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    time
                    EventTypeBadge(type: event.type)
                    subject
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var time: some View {
        Text(event.receivedAt.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute().second()))
            .font(.code(.caption))
            .foregroundStyle(.secondary)
    }

    private var subject: some View {
        Text(title.map(event.summary(title:)) ?? event.summary)
            .font(.callout)
            .truncationMode(.tail)
            .contentTransition(.interpolate)
            .animation(reduceMotion ? nil : .snappy, value: title)
    }
}

struct EventInspector: View {
    let event: NotificationEvent

    @Environment(ActivityStore.self) private var activity
    @State private var built: Built?
    @State private var collapsed: Set<Int> = []

    /// Shown only for its own event, so `version` (the event's time) is never paired
    /// with another event's text.
    private struct Built {
        let eventID: NotificationEvent.ID
        let document: ResponseDocument
    }

    private var document: ResponseDocument? {
        built.flatMap { $0.eventID == event.id ? $0.document : nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                EventTypeBadge(type: event.type)
                Text(event.receivedAt.formatted(.dateTime.hour().minute().second()))
                    .font(.code(.caption))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Clipboard.copy(document?.text ?? event.raw)
                } label: {
                    Label("Copy Payload", systemImage: "doc.on.doc")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Copy payload")
                Button {
                    activity.selectedEventID = nil
                } label: {
                    Label("Hide Info", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Hide Info (⌘I)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if let document {
                CodeTextView(
                    text: document.text,
                    tokens: document.tokens,
                    folds: document.folds,
                    collapsed: $collapsed,
                    wrap: true,
                    version: event.receivedAt
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.container, edges: .bottom)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: event.id) {
            let id = event.id
            let raw = event.raw
            let document = await Task.detached(priority: .userInitiated) {
                ResponseDocument.build(body: Data(raw.utf8), contentType: "application/json")
            }.value
            guard !Task.isCancelled else { return }
            collapsed = []
            built = Built(eventID: id, document: document)
        }
    }
}
