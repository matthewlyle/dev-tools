import Foundation

struct NotificationEvent: Identifiable, Sendable, Hashable {
    let id: UUID
    let receivedAt: Date
    let type: String
    let raw: String
    let node: Node?
    /// The library item the payload is about (`ratingKey`, a timeline's
    /// `itemID`, or a `/library/metadata/<n>` key); digits only.
    let ratingKey: String?
    let state: String?
    /// Playback position in milliseconds.
    let viewOffset: Int?
    /// The running session the event reports on, if any.
    let session: Session?
    /// Percent complete, as a transcode reports it.
    let progress: Double?
    /// The row's line from the payload alone: its own title when it has one,
    /// otherwise an identifying key.
    let summary: String
    private let line: Line
    private let titled: Bool
    private let payload: Node?

    enum Session: Hashable, Sendable {
        /// A `playing` event's `sessionKey`.
        case playback(String)
        /// A transcode event's `/transcode/sessions/…` key.
        case transcode(String)
    }

    /// An attribute of the payload itself (the container's first child).
    func value(_ name: String) -> String? {
        payload?[name].flatMap { $0.isEmpty ? nil : $0 }
    }

    /// `2:53`, or `1:02:07` from an hour on.
    static func position(milliseconds ms: Int) -> String {
        Duration.milliseconds(ms).formatted(.time(pattern: ms >= 3_600_000 ? .hourMinuteSecond : .minuteSecond))
    }

    /// The item to look a title up for: set only when the payload names it
    /// by key alone, as a playing session or an untitled timeline entry does.
    var titleKey: String? { titled ? nil : ratingKey }

    /// The row's line with a looked-up item title in place of the key.
    func summary(title: String) -> String {
        var line = line
        line.subject = title
        return line.text
    }

    /// Builds an event from a raw JSON frame; the payload is wrapped in
    /// `NotificationContainer`, whose `type` names the event.
    static func make(raw: String, receivedAt: Date = .now) -> NotificationEvent {
        let node = JSONNodeParser.parse(Data(raw.utf8))
        let container = node.flatMap { root in
            root.name == "NotificationContainer" ? root : root.children.first { $0.name == "NotificationContainer" } ?? root
        }
        let type = container?["type"].flatMap { $0.isEmpty ? nil : $0 } ?? "message"
        let facts = Facts(container, type: type)
        return NotificationEvent(
            id: UUID(),
            receivedAt: receivedAt,
            type: type,
            raw: raw,
            node: node,
            ratingKey: facts.ratingKey,
            state: facts.state,
            viewOffset: facts.viewOffset,
            session: facts.session,
            progress: facts.progress,
            summary: facts.line.text,
            line: facts.line,
            titled: facts.titled,
            payload: container?.children.first
        )
    }

    /// A library item's name as a person says it, from its
    /// `/library/metadata/<ratingKey>` response: an episode as
    /// `Show — S2 E3 · Title`, a movie as `Title (1995)`, a track as
    /// `Artist — Title`, anything else by its title.
    static func itemTitle(metadata root: Node) -> String? {
        guard let item = root.children.first(where: { $0.name == "Metadata" }) ?? root.children.first,
              let title = nonEmpty(item["title"])
        else { return nil }
        switch item["type"] {
        case "episode":
            let code: String? = switch (nonEmpty(item["parentIndex"]), nonEmpty(item["index"])) {
            case let (season?, episode?): "S\(season) E\(episode)"
            case let (nil, episode?): "E\(episode)"
            default: nil
            }
            let head = [nonEmpty(item["grandparentTitle"]), code].compactMap { $0 }.joined(separator: " — ")
            return head.isEmpty ? title : "\(head) · \(title)"
        case "movie":
            return nonEmpty(item["year"]).map { "\(title) (\($0))" } ?? title
        case "track":
            let artist = nonEmpty(item["originalTitle"]) ?? nonEmpty(item["grandparentTitle"])
            return artist.map { "\($0) — \(title)" } ?? title
        default:
            return title
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        value.flatMap { $0.isEmpty ? nil : $0 }
    }
}

/// `state · subject · progress · position`, each part only when present.
private struct Line: Sendable, Hashable {
    var lead: String?
    var subject: String?
    var progress: String?
    var offset: String?

    var text: String {
        [lead, subject, progress, offset].compactMap { $0 }.joined(separator: " · ")
    }
}

/// What a notification payload says about itself.
private struct Facts {
    var state: String?
    var viewOffset: Int?
    var ratingKey: String?
    var session: NotificationEvent.Session?
    var progress: Double?
    var titled = false
    var line = Line()

    /// Identifying values for a payload with nothing human to show, most
    /// telling first; bare ids carry their name.
    private static let identifiers = ["key", "ratingKey", "itemID", "queueID", "reachability", "identifier", "clientIdentifier"]
    private static let namedIdentifiers: Set<String> = ["ratingKey", "itemID", "queueID"]

    init(_ container: Node?, type: String) {
        guard let container else { return }
        // The payload is the first child (e.g. PlaySessionStateNotification);
        // activities nest one level deeper (ActivityNotification > Activity).
        var candidates: [Node] = []
        if let payload = container.children.first {
            candidates.append(payload)
            candidates.append(contentsOf: payload.children.prefix(2))
        } else {
            candidates.append(container)
        }
        func value(_ name: String) -> String? {
            for node in candidates {
                if let value = node[name], !value.isEmpty { return value }
            }
            return nil
        }

        state = value("state")
        viewOffset = value("viewOffset").flatMap { Int($0) }
        ratingKey = [value("ratingKey"), value("itemID"), value("key").flatMap(Self.metadataKey)]
            .compactMap { $0 }
            .first { !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }

        if type == "playing", let key = value("sessionKey") {
            session = .playback(key)
        } else if type.hasPrefix("transcodeSession."), let key = value("key") {
            session = .transcode(key)
        }
        progress = value("progress").flatMap(Double.init)

        let human = [value("title"), value("subtitle")].compactMap { $0 }
        let named = human.isEmpty ? (value("message") ?? value("description")) : human.joined(separator: " · ")
        titled = named != nil

        line.lead = state.map(Self.displayState) ?? value("event").map(Self.capitalized)
        line.subject = named
        if named == nil {
            for name in Self.identifiers {
                guard let id = value(name) else { continue }
                line.subject = Self.namedIdentifiers.contains(name) ? "\(name) \(id)" : id
                break
            }
        }
        line.progress = value("progress").map { raw in progress.map { "\(Int($0.rounded()))%" } ?? raw }
        line.offset = viewOffset.map(NotificationEvent.position(milliseconds:))
    }

    /// `/library/metadata/28282/children` → `28282`.
    private static func metadataKey(_ key: String) -> String? {
        let prefix = "/library/metadata/"
        guard key.hasPrefix(prefix) else { return nil }
        return String(key.dropFirst(prefix.count).prefix { $0 != "/" })
    }

    /// Playback states are words; a timeline entry's is a bare number.
    private static func displayState(_ state: String) -> String {
        Int(state) == nil ? capitalized(state) : "state \(state)"
    }

    private static func capitalized(_ word: String) -> String {
        word.prefix(1).uppercased() + word.dropFirst()
    }
}
