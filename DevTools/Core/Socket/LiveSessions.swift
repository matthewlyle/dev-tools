import Foundation

/// The playback and transcode sessions the notification stream says are
/// running, each as its latest event, in the order they were first seen. A
/// playback ends when it reports `stopped`; a transcode on
/// `transcodeSession.end`.
struct LiveSessions: Equatable {
    private(set) var playback: [NotificationEvent] = []
    private(set) var transcodes: [NotificationEvent] = []

    func contains(_ session: NotificationEvent.Session) -> Bool {
        (playback + transcodes).contains { $0.session == session }
    }

    mutating func apply(_ event: NotificationEvent) {
        switch event.session {
        case .playback:
            Self.update(&playback, with: event, ends: event.state == "stopped")
        case .transcode:
            Self.update(&transcodes, with: event, ends: event.type == "transcodeSession.end")
        case nil:
            return
        }
    }

    private static func update(_ list: inout [NotificationEvent], with event: NotificationEvent, ends: Bool) {
        let index = list.firstIndex { $0.session == event.session }
        switch (index, ends) {
        case (let index?, true): list.remove(at: index)
        case (let index?, false): list[index] = event
        case (nil, false): list.append(event)
        case (nil, true): return
        }
    }
}
