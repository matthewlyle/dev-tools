import SwiftUI

/// Live event list with a payload inspector beside it.
struct ActivityEventsView: View {
    @Environment(ActivityStore.self) private var activity

    var body: some View {
        @Bindable var activity = activity

        HSplitView {
            List(activity.visibleEvents, selection: $activity.selectedEventID) { event in
                EventRow(event: event)
                    .tag(event.id)
            }
            .listStyle(.inset)
            .frame(minWidth: 320, idealWidth: 460)
            .overlay {
                if activity.visibleEvents.isEmpty {
                    ContentUnavailableView(
                        activity.status.isActive ? "Waiting for Events" : "Not Connected",
                        systemImage: "dot.radiowaves.left.and.right",
                        description: Text(activity.status.isActive
                            ? "Start playback or a library scan on any client."
                            : "Connect in the Activity panel to stream notifications.")
                    )
                }
            }

            EventInspector(event: activity.selectedEvent)
                .frame(minWidth: 320)
        }
        .navigationTitle("Activity")
        .navigationSubtitle(subtitle)
    }

    private var subtitle: String {
        var parts = ["\(activity.events.count.formatted()) events"]
        if !activity.hiddenTypes.isEmpty { parts.append("\(activity.visibleEvents.count.formatted()) shown") }
        if activity.isPaused { parts.append("paused") }
        return parts.joined(separator: " · ")
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

/// Pretty-printed, highlighted, foldable payload of the selected event.
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
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(document?.text ?? event.raw, forType: .string)
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
                        version: event.receivedAt
                    )
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
