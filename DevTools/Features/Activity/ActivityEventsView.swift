import SwiftUI

/// The event list under its connection control. The selected event's
/// payload opens in the detail pane's inspector (`SectionInspector`); the
/// list and the control are views of their own so only they redraw per
/// incoming frame, and this body reads nothing but the selection.
struct ActivityEventsView: View {
    @Environment(ActivityStore.self) private var activity
    @Environment(\.sectionIsActive) private var isActive
    @Environment(\.isCompactWidth) private var compact

    var body: some View {
        EventList()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // A compact width carries the control as the tab bar's
                // accessory (`MainSplitView`); elsewhere it floats over the
                // events as a capsule, the one custom glass in the app: a
                // control above content, which the HIG allows sparingly.
                if !compact {
                    ActivityConnectionControl()
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .glassEffect(.regular, in: .capsule)
                        .frame(maxWidth: 560)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }
            }
            .focusedSceneValue(
                \.showMediaInfo,
                isActive && activity.selectedEvent != nil
                    ? ShowMediaInfoAction(visible: true) { activity.selectedEventID = nil }
                    : nil
            )
    }
}

/// The connection: status, count, Clear, and Connect or Disconnect. As the
/// tab bar's accessory it's one line, and inline beside a minimized tab bar
/// it keeps only the status and the button.
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
                    .contentTransition(.interpolate)
                if activity.status.isActive, !inline {
                    Text("\(activity.receivedCount.formatted()) received")
                        .font(.code(.caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help("Messages received on the wire since connecting")
                }
                Spacer(minLength: 8)
                if !activity.events.isEmpty, !inline {
                    Button {
                        activity.clear()
                    } label: {
                        Label("Clear Events", systemImage: "trash")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .help("Clear events")
                }
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
            // The accessory is one line tall; the error stays where there's
            // room for it.
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

    var body: some View {
        @Bindable var activity = activity
        let visible = activity.visibleEvents

        ZStack {
            if activity.events.isEmpty, !activity.status.isActive {
                FillingScrollView {
                    disconnected
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .restingStateTransition(rising: true)
                .zIndex(1)
            } else {
                List(visible, selection: $activity.selectedEventID) { event in
                    EventRow(event: event, title: activity.title(for: event))
                        .tag(event.id)
                        .listRowSeparator(.hidden)
                        .sectionListRow(selected: event.id == activity.selectedEventID)
                }
                // A row tap on iPadOS runs the list's primary action — the
                // platform's "open this item" — while macOS runs it on
                // double-click and keeps native click and arrow-key
                // selection. Selecting here opens the inspector from a tap on
                // both; a tap gesture instead would swallow the macOS table's
                // own selection.
                .contextMenu(forSelectionType: NotificationEvent.ID.self) { _ in
                } primaryAction: { ids in
                    if let id = ids.first { activity.selectedEventID = id }
                }
                .sectionListStyle()
                .overlay {
                    ZStack {
                        if visible.isEmpty, activity.status.isActive {
                            ZeroState(text: "Waiting for events. Start playback or a library scan on any client.")
                                .restingStateTransition(rising: true)
                        }
                    }
                }
                .animation(reduceMotion ? nil : .smooth, value: activity.events.first?.id)
                .transition(.identity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
            ZeroState(text: "Connect to watch playback, library scans, and other server activity as it happens.")
        }
    }
}

private struct EventRow: View {
    let event: NotificationEvent
    let title: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(event.receivedAt.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute().second().secondFraction(.fractional(3))))
                .font(.code(.caption))
                .foregroundStyle(.secondary)
            EventTypeBadge(type: event.type)
            Text(title.map(event.summary(title:)) ?? event.summary)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)
                .contentTransition(.interpolate)
                .animation(reduceMotion ? nil : .snappy, value: title)
        }
        .padding(.vertical, 2)
    }
}

struct EventInspector: View {
    let event: NotificationEvent

    @Environment(ActivityStore.self) private var activity
    @State private var built: Built?
    @State private var collapsed: Set<Int> = []

    /// A payload document and the event it was built from. The text view is
    /// only shown for a document that belongs to `event`, so its `version`
    /// (the event's time) can never be paired with another event's text.
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
                Text(event.receivedAt.formatted(.dateTime.hour().minute().second().secondFraction(.fractional(3))))
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
                    version: event.receivedAt,
                    header: AnyView(EmptyView())
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
