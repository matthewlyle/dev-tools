import Foundation

struct LiveSessions: Equatable {
    typealias Session = NotificationEvent.Session

    struct Playback: Equatable {
        let session: Session
        var ratingKey: String?
        var state: String?
        var viewOffset: Int?
    }

    struct Transcode: Equatable {
        let session: Session
        var subject: String?
        var progress: Double?
        var speed: Double?
        var throttled = false

        init(session: Session, node: Node) {
            self.session = session
            func value(_ name: String) -> String? { node[name].flatMap { $0.isEmpty ? nil : $0 } }
            if let source = value("sourceVideoCodec"), let target = value("videoCodec"), source != target {
                subject = "\(source) → \(target)"
            } else {
                subject = value("context").map { $0.prefix(1).uppercased() + $0.dropFirst() }
            }
            progress = value("progress").flatMap(Double.init)
            speed = value("speed").flatMap(Double.init)
            throttled = value("throttled") == "1" || value("throttled") == "true"
        }
    }

    private(set) var playback: [Playback] = []
    private(set) var transcodes: [Transcode] = []

    var isEmpty: Bool { playback.isEmpty && transcodes.isEmpty }

    func contains(_ session: Session) -> Bool {
        playback.contains { $0.session == session } || transcodes.contains { $0.session == session }
    }

    mutating func apply(_ event: NotificationEvent) {
        switch event.session {
        case let session? where session.isPlayback:
            let row = Playback(session: session, ratingKey: event.ratingKey, state: event.state, viewOffset: event.viewOffset)
            Self.update(&playback, with: row, ends: event.state == "stopped")
        case let session?:
            guard let payload = event.payload else { return }
            Self.update(&transcodes, with: Transcode(session: session, node: payload), ends: event.type == "transcodeSession.end")
        case nil:
            return
        }
    }

    /// A session the stream already reported keeps that report, which is at least as new.
    mutating func seed(statusSessions root: Node) {
        for item in root.children {
            guard let key = item["sessionKey"], !key.isEmpty else { continue }
            let session = Session.playback(key)
            if !contains(session) {
                let state = item.children.first { $0.name == "Player" }?["state"]
                playback.append(Playback(session: session, ratingKey: item["ratingKey"], state: state, viewOffset: item["viewOffset"].flatMap { Int($0) }))
            }
            if let node = item.children.first(where: { $0.name == "TranscodeSession" }), let key = node["key"] {
                let session = Session.transcode(key: key)
                if !contains(session) { transcodes.append(Transcode(session: session, node: node)) }
            }
        }
    }

    private static func update<Row: Equatable & SessionRow>(_ list: inout [Row], with row: Row, ends: Bool) {
        let index = list.firstIndex { $0.session == row.session }
        switch (index, ends) {
        case (let index?, true): list.remove(at: index)
        case (let index?, false): list[index] = row
        case (nil, false): list.append(row)
        case (nil, true): return
        }
    }
}

private protocol SessionRow {
    var session: LiveSessions.Session { get }
}

extension LiveSessions.Playback: SessionRow {}
extension LiveSessions.Transcode: SessionRow {}
