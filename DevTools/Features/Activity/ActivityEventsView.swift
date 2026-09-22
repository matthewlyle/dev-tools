import SwiftUI

/// The event list, with the selected event's payload in an inspector — the
/// same list-plus-inspector shape as the Media section, on both platforms.
struct ActivityEventsView: View {
    @Environment(ActivityStore.self) private var activity
    @Environment(\.sectionIsActive) private var isActive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showInspector = false

    var body: some View {
        @Bindable var activity = activity

        Group {
            if activity.events.isEmpty, !activity.status.isActive {
                // Disconnected with nothing captured: the Connect button in the
                // Activity panel is the only affordance, so this pane stays empty.
                FillingScrollView { Color.clear }
            } else {
                List(activity.visibleEvents, selection: $activity.selectedEventID) { event in
                    EventRow(event: event)
                        .tag(event.id)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .overlay {
                    if activity.visibleEvents.isEmpty, activity.status.isActive {
                        ContentUnavailableView(
                            "Waiting for Events",
                            systemImage: "dot.radiowaves.left.and.right",
                            description: Text("Start playback or a library scan on any client.")
                        )
                    }
                }
                .animation(reduceMotion ? nil : .smooth, value: activity.events.first?.id)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .inspector(isPresented: Binding(get: { isActive && showInspector }, set: { showInspector = $0 })) {
            EventInspector(event: activity.selectedEvent)
                .inspectorColumnWidth(min: 320, ideal: 460, max: 800)
        }
        .onChange(of: activity.visibleEvents.isEmpty, initial: true) { _, isEmpty in
            showInspector = !isEmpty
        }
    }
}

private struct EventRow: View {
    let event: NotificationEvent

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(event.receivedAt.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute().second().secondFraction(.fractional(3))))
                .font(.code(.caption))
                .foregroundStyle(.secondary)
            EventTypeBadge(type: event.type)
            Text(event.summary)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.vertical, 2)
    }
}

private struct EventInspector: View {
    let event: NotificationEvent?

    @State private var document: ResponseDocument?
    @State private var collapsed: Set<Int> = []

    var body: some View {
        if let event {
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
                collapsed = []
                document = nil
                let raw = event.raw
                document = await Task.detached {
                    ResponseDocument.build(body: Data(raw.utf8), contentType: "application/json")
                }.value
            }
        } else {
            ContentUnavailableView(
                "No Event Selected",
                systemImage: "waveform",
                description: Text("Select an event to inspect its payload.")
            )
        }
    }
}
