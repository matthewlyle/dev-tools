import SwiftUI

struct ActivityFiltersView: View {
    @Environment(ActivityStore.self) private var activity
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var loading: Bool { activity.status.isActive && !activity.sessionsLoaded }

    var body: some View {
        ZStack {
            if loading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity.animation(.easeOut(duration: 0.1)))
            } else {
                list
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)))
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.3), value: loading)
    }

    private var list: some View {
        List {
            if !activity.live.isEmpty {
                Section {
                    focusRow(nil) {
                        HStack {
                            Text("All Events")
                                .font(.callout)
                            Spacer()
                            Text(activity.events.count.formatted())
                                .font(.code(.caption))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listSectionSeparator(.hidden)
            }
            if !activity.live.playback.isEmpty {
                Section("Now Playing") {
                    ForEach(activity.live.playback, id: \.session) { playback in
                        focusRow(playback.session) {
                            PlaybackRow(playback: playback, title: playback.ratingKey.flatMap(activity.title(ratingKey:)))
                        }
                    }
                }
                .listSectionSeparator(.hidden)
            }
            if !activity.live.transcodes.isEmpty {
                Section("Transcodes") {
                    ForEach(activity.live.transcodes, id: \.session) { transcode in
                        focusRow(transcode.session) { TranscodeRow(transcode: transcode) }
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

    private func focusRow(_ session: NotificationEvent.Session?, @ViewBuilder label: () -> some View) -> some View {
        let chosen = activity.focusedSession == session
        return Button {
            activity.focusedSession = session
        } label: {
            label()
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
        .sectionListButtonRow(selected: chosen)
        .help(session == nil ? "Show all events" : "Show only this session's events")
    }
}

private struct PlaybackRow: View {
    let playback: LiveSessions.Playback
    let title: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var detail: String {
        [playback.state.map { $0.prefix(1).uppercased() + $0.dropFirst() }, playback.viewOffset.map(NotificationEvent.position(milliseconds:))]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title ?? playback.ratingKey.map { "ratingKey \($0)" } ?? "Unknown item")
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

private struct TranscodeRow: View {
    let transcode: LiveSessions.Transcode

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var subject: String {
        if let subject = transcode.subject { return subject }
        if case .transcode(let id) = transcode.session { return id }
        return "Transcode"
    }

    private var detail: String {
        [
            transcode.progress.map { "\(Int($0.rounded()))%" },
            transcode.speed.map { "\($0.formatted(.number.precision(.fractionLength(1))))×" },
            transcode.throttled ? "throttled" : nil,
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
