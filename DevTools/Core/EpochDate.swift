import SwiftUI

enum EpochDate {
    /// `originallyAvailableAt` is a `YYYY-MM-DD` string, not epoch seconds.
    static func isEpochName(_ name: String) -> Bool {
        let stem = stem(of: name)
        return stem == "timestamp" || (stem.hasSuffix("At") && stem != "originallyAvailableAt")
    }

    static func acceptsRelative(_ name: String) -> Bool {
        stem(of: name) != name
    }

    private static func stem(of name: String) -> String {
        String(name.prefix { !"<>=!".contains($0) })
    }

    static func date(_ value: String) -> Date? {
        guard let seconds = TimeInterval(value.trimmingCharacters(in: .whitespaces)), seconds > 1_000_000_000 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    static func epoch(_ date: Date) -> String {
        String(Int(date.timeIntervalSince1970))
    }

    static func describe(_ value: String) -> String? {
        if let date = date(value) { return date.formatted(date: .abbreviated, time: .shortened) }
        return relative(value)
    }

    static func relative(_ value: String) -> String? {
        guard let match = value.trimmingCharacters(in: .whitespaces).wholeMatch(of: /([+-])(\d+)(mon|m|h|d|w|y)?/),
              let amount = Int(match.2), amount > 0
        else { return nil }
        let unit: (one: String, many: String) = switch match.3 {
        case "m"?: ("minute", "minutes")
        case "h"?: ("hour", "hours")
        case "d"?: ("day", "days")
        case "w"?: ("week", "weeks")
        case "mon"?: ("month", "months")
        case "y"?: ("year", "years")
        default: ("second", "seconds")
        }
        let phrase = "\(amount) \(amount == 1 ? unit.one : unit.many)"
        return match.1 == "-" ? "\(phrase) ago" : "in \(phrase)"
    }

    static let recent = ["-1d", "-1w", "-1mon", "-1y"]
}

struct EpochDateButton: View {
    @Binding var value: String
    var relative = false

    @State private var picking = false

    var body: some View {
        Button {
            picking = true
        } label: {
            Label("Choose Date", systemImage: "calendar")
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .help("Choose a date")
        .popover(isPresented: $picking) {
            VStack(alignment: .leading, spacing: 12) {
                DatePicker("Date", selection: date, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                if relative {
                    Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                        GridRow {
                            choice(EpochDate.recent[0])
                            choice(EpochDate.recent[1])
                        }
                        GridRow {
                            choice(EpochDate.recent[2])
                            choice(EpochDate.recent[3])
                        }
                    }
                }
                Button("Now") {
                    value = EpochDate.epoch(.now)
                    picking = false
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }
            .controlSize(.small)
            // A graphical picker has no width of its own, and a popover kept on iPhone
            // sizes to its content, so without one it collapses to a column of digits.
            .frame(width: 320)
            .padding()
            .presentationCompactAdaptation(.popover)
        }
    }

    private func choice(_ relative: String) -> some View {
        Button(EpochDate.relative(relative)?.capitalized ?? relative) {
            value = relative
            picking = false
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity)
    }

    private var date: Binding<Date> {
        Binding(
            get: { EpochDate.date(value) ?? .now },
            set: { value = EpochDate.epoch($0) }
        )
    }
}

struct EpochReadout: View {
    let value: String

    var body: some View {
        if let text = EpochDate.describe(value) {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .contentTransition(.interpolate)
        }
    }
}
