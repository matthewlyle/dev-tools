import SwiftUI

/// The event list. The selected event's payload opens in the detail pane's
/// inspector (`SectionInspector`); the list lives in its own view so only it
/// redraws per incoming frame, and this body reads nothing but the selection.
struct ActivityEventsView: View {
    @Environment(ActivityStore.self) private var activity
    @Environment(\.sectionIsActive) private var isActive

    var body: some View {
        EventList()
            .focusedSceneValue(
                \.showMediaInfo,
                isActive && activity.selectedEvent != nil
                    ? ShowMediaInfoAction(visible: true) { activity.selectedEventID = nil }
                    : nil
            )
    }
}

private struct EventList: View {
    @Environment(ActivityStore.self) private var activity
    @Environment(ServerStore.self) private var servers
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var selectedServer: ConnectedServer? {
        servers.selected.flatMap { servers.connectedServer(for: $0) }
    }

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
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
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
            ContentUnavailableView {
                Label("Couldn't Connect", systemImage: "exclamationmark.triangle")
            } description: {
                Text("\(message) Check that the server is reachable, then try again.")
            } actions: {
                connectButton("Try Again")
            }
        } else {
            // The list column's Connect can be hidden on iPad, so the resting
            // state carries its own.
            ZeroState(text: "Connect to watch playback, library scans, and other server activity as it happens.") {
                connectButton("Connect")
                    .controlSize(.small)
            }
        }
    }

    private func connectButton(_ title: String) -> some View {
        Button(title) {
            guard let selectedServer else { return }
            activity.connect(to: selectedServer)
        }
        .disabled(selectedServer == nil)
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
