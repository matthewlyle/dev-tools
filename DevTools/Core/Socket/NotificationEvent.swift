import Foundation

/// One message from the server's notification feed.
struct NotificationEvent: Identifiable, Sendable, Hashable {
    let id: UUID
    let receivedAt: Date
    let type: String
    /// The message exactly as received.
    let raw: String
    let node: Node?
    let summary: String

    /// Builds an event from a raw JSON frame; the payload is wrapped in
    /// `NotificationContainer`, whose `type` names the event.
    static func make(raw: String, receivedAt: Date = .now) -> NotificationEvent {
        let node = JSONNodeParser.parse(Data(raw.utf8))
        let container = node.flatMap { root in
            root.name == "NotificationContainer" ? root : root.children.first { $0.name == "NotificationContainer" } ?? root
        }
        let type = container?["type"].flatMap { $0.isEmpty ? nil : $0 } ?? "message"
        return NotificationEvent(
            id: UUID(),
            receivedAt: receivedAt,
            type: type,
            raw: raw,
            node: node,
            summary: summarize(container)
        )
    }

    /// Attributes worth surfacing in a one-line summary, in priority order.
    private static let summaryAttributes = [
        "state", "event", "title", "message", "description", "key", "ratingKey", "viewOffset", "progress", "queueID", "reachability", "identifier", "clientIdentifier",
    ]

    private static func summarize(_ container: Node?) -> String {
        guard let container else { return "" }
        // The payload is the first child (e.g. PlaySessionStateNotification);
        // activities nest one level deeper.
        var candidates: [Node] = []
        if let payload = container.children.first {
            candidates.append(payload)
            candidates.append(contentsOf: payload.children.prefix(2))
        } else {
            candidates.append(container)
        }

        var parts: [String] = []
        for name in summaryAttributes where parts.count < 3 {
            for node in candidates {
                if let value = node[name], !value.isEmpty {
                    parts.append(Self.display(name: name, value: value))
                    break
                }
            }
        }
        return parts.joined(separator: " · ")
    }

    private static func display(name: String, value: String) -> String {
        switch name {
        case "viewOffset", "progress", "ratingKey", "queueID":
            if name == "viewOffset", let ms = Int(value) {
                return Duration.milliseconds(ms).formatted(.time(pattern: ms >= 3_600_000 ? .hourMinuteSecond : .minuteSecond))
            }
            return "\(name) \(value)"
        default:
            return value
        }
    }
}
