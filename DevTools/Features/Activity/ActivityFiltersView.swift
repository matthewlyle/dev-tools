import SwiftUI

/// The Activity list pane: which event types the events show. Like every
/// section's list it only filters what's on the right; the connection and
/// its controls are the events' footer (`ActivityStatusBar`).
struct ActivityFiltersView: View {
    @Environment(ActivityStore.self) private var activity

    var body: some View {
        List {
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
        .overlay {
            if activity.typeCounts.isEmpty {
                ZeroState(text: "Event types appear here as events arrive.")
            }
        }
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
