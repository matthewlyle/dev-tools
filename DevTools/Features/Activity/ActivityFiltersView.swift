import SwiftUI

/// The Activity list pane: what's running on the server and which event
/// types the events show. Like every section's list it only narrows what's
/// on the right — a session to its own events, types on and off; the
/// connection and its controls are the events' footer. Until events arrive
/// it's blank: the events pane's own zero state says what to do, and a
/// second one here would compete with it.
struct ActivityFiltersView: View {
    @Environment(ActivityStore.self) private var activity

    var body: some View {
        List {
            if !activity.live.playback.isEmpty {
                Section("Now Playing") {
                    ForEach(activity.live.playback, id: \.session) { event in
                        sessionRow(event) { PlaybackRow(event: event, title: activity.title(for: event)) }
                    }
                }
                .listSectionSeparator(.hidden)
            }
            if !activity.live.transcodes.isEmpty {
                Section("Transcodes") {
                    ForEach(activity.live.transcodes, id: \.session) { event in
                        sessionRow(event) { TranscodeRow(event: event) }
                    }
                }
                .listSectionSeparator(.hidden)
            }
            if !activity.typeCounts.isEmpty {
                Section("Event Types") {
                    ForEach(activity.typeCounts.sorted { $0.key < $1.key }, id: \.key) { type, count in
                        Toggle(isOn: shown(type, in: activity)) {
                            HStack {
                                EventTypeBadge(type: type)
                                Spacer()
                                Text(count.formatted())
                                    .font(.code(.caption))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listRowSeparator(.hidden)
                .sectionListRow()
                .listSectionSeparator(.hidden)
            }
        }
        .sectionListStyle()
    }

    /// Picking a session narrows the events to it; picking it again widens
    /// them back.
    private func sessionRow(_ event: NotificationEvent, @ViewBuilder label: () -> some View) -> some View {
        let focused = activity.focusedSession == event.session
        return Button {
            activity.focusedSession = focused ? nil : event.session
        } label: {
            label()
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
        .sectionListButtonRow(selected: focused)
        .help(focused ? "Show all events" : "Show only this session's events")
    }
}

/// A playback: the item's name, then its state and position, which move in
/// place as the session reports.
private struct PlaybackRow: View {
    let event: NotificationEvent
    let title: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var detail: String {
        [event.state.map { $0.prefix(1).uppercased() + $0.dropFirst() }, event.viewOffset.map(NotificationEvent.position(milliseconds:))]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title ?? event.ratingKey.map { "ratingKey \($0)" } ?? "Unknown item")
                .font(.callout)
                .lineLimit(1)
                .contentTransition(.interpolate)
                .animation(reduceMotion ? nil : .snappy, value: title)
            Text(detail)
                .font(.code(.caption))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .snappy, value: detail)
        }
        .padding(.vertical, 2)
    }
}

/// A transcode: what it converts (the video codec change where the payload
/// names both), then its progress and speed.
private struct TranscodeRow: View {
    let event: NotificationEvent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var subject: String {
        if let source = event.value("sourceVideoCodec"), let target = event.value("videoCodec"), source != target {
            return "\(source) → \(target)"
        }
        if let context = event.value("context") {
            return context.prefix(1).uppercased() + context.dropFirst()
        }
        if case .transcode(let key) = event.session {
            return key.split(separator: "/").last.map(String.init) ?? key
        }
        return "Transcode"
    }

    private var detail: String {
        [
            event.progress.map { "\(Int($0.rounded()))%" },
            event.value("speed").flatMap(Double.init).map { "\($0.formatted(.number.precision(.fractionLength(1))))×" },
            event.value("throttled") == "1" || event.value("throttled") == "true" ? "throttled" : nil,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(subject)
                .font(.code(.callout))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(detail)
                .font(.code(.caption))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .snappy, value: detail)
        }
        .padding(.vertical, 2)
    }
}

/// The same filter as a toolbar menu, where there's no list pane beside the
/// events: a compact width, whose Activity tab roots the events themselves.
struct ActivityTypeMenu: View {
    @Environment(ActivityStore.self) private var activity

    var body: some View {
        Menu {
            ForEach(activity.typeCounts.sorted { $0.key < $1.key }, id: \.key) { type, count in
                Toggle("\(type) (\(count.formatted()))", isOn: shown(type, in: activity))
            }
        } label: {
            Label(
                "Event Types",
                systemImage: activity.hiddenTypes.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill"
            )
        }
        .disabled(activity.typeCounts.isEmpty)
        .help("Filter events by type")
    }
}

@MainActor
private func shown(_ type: String, in activity: ActivityStore) -> Binding<Bool> {
    Binding(
        get: { !activity.hiddenTypes.contains(type) },
        set: { _ in activity.toggle(type: type) }
    )
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
