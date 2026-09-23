import Foundation
import Testing
@testable import DevTools

struct LiveSessionsTests {
    private func playing(_ sessionKey: String, state: String, offset: Int = 0) -> NotificationEvent {
        NotificationEvent.make(raw: """
        {"NotificationContainer":{"type":"playing","PlaySessionStateNotification":[
          {"sessionKey":"\(sessionKey)","ratingKey":"28282","viewOffset":\(offset),"state":"\(state)"}
        ]}}
        """)
    }

    private func transcode(_ type: String, id: String, progress: Double = 0) -> NotificationEvent {
        NotificationEvent.make(raw: """
        {"NotificationContainer":{"type":"transcodeSession.\(type)","TranscodeSession":[
          {"key":"/transcode/sessions/\(id)","progress":\(progress)}
        ]}}
        """)
    }

    @Test func eventsNameTheSessionTheyReportOn() {
        #expect(playing("12", state: "playing").session == .playback("12"))
        #expect(transcode("update", id: "abc", progress: 12.6).session == .transcode("/transcode/sessions/abc"))
        #expect(transcode("update", id: "abc", progress: 12.6).progress == 12.6)
        let timeline = NotificationEvent.make(raw: #"{"NotificationContainer":{"type":"timeline","TimelineEntry":[{"itemID":"1","state":5}]}}"#)
        #expect(timeline.session == nil)
    }

    @Test func aPlaybackShowsItsLatestFrameUntilItStops() {
        var live = LiveSessions()
        live.apply(playing("12", state: "playing", offset: 1_000))
        live.apply(playing("13", state: "playing"))
        live.apply(playing("12", state: "paused", offset: 5_000))
        #expect(live.playback.map(\.session) == [.playback("12"), .playback("13")])
        #expect(live.playback.first?.state == "paused")
        #expect(live.playback.first?.viewOffset == 5_000)

        live.apply(playing("12", state: "stopped"))
        #expect(live.playback.map(\.session) == [.playback("13")])
        #expect(!live.contains(.playback("12")))
    }

    @Test func aTranscodeRunsFromStartToEnd() {
        var live = LiveSessions()
        live.apply(transcode("start", id: "abc"))
        live.apply(transcode("update", id: "abc", progress: 40))
        #expect(live.transcodes.first?.progress == 40)
        live.apply(transcode("end", id: "abc"))
        #expect(live.transcodes.isEmpty)
    }

    @Test func anEndForAnUnseenSessionAddsNothing() {
        var live = LiveSessions()
        live.apply(playing("12", state: "stopped"))
        live.apply(transcode("end", id: "abc"))
        #expect(live.playback.isEmpty && live.transcodes.isEmpty)
    }
}
