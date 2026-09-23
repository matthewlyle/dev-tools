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
          {"key":"/transcode/sessions/\(id)","progress":\(progress),"speed":1.25,"throttled":true,"sourceVideoCodec":"hevc","videoCodec":"h264"}
        ]}}
        """)
    }

    @Test func eventsNameTheSessionTheyReportOn() {
        #expect(playing("12", state: "playing").session == .playback("12"))
        #expect(transcode("update", id: "abc").session == .transcode("abc"))
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
        let row = live.transcodes.first
        #expect(row?.progress == 40)
        #expect(row?.speed == 1.25)
        #expect(row?.throttled == true)
        #expect(row?.subject == "hevc → h264")
        live.apply(transcode("end", id: "abc"))
        #expect(live.transcodes.isEmpty)
    }

    @Test func anEndForAnUnseenSessionAddsNothing() {
        var live = LiveSessions()
        live.apply(playing("12", state: "stopped"))
        live.apply(transcode("end", id: "abc"))
        #expect(live.isEmpty)
    }

    @Test func statusSessionsSeedWhatTheStreamHasNotReported() throws {
        let root = try #require(JSONNodeParser.parse(Data(#"""
        {"MediaContainer":{"size":2,"Metadata":[
          {"sessionKey":"12","ratingKey":"28282","type":"movie","title":"Heat","year":1995,"viewOffset":90000,
           "Player":{"state":"paused"},
           "TranscodeSession":{"key":"/transcode/sessions/abc","progress":7,"context":"streaming"}},
          {"sessionKey":"13","ratingKey":"4","type":"movie","title":"Ronin","viewOffset":1000,"Player":{"state":"playing"}}
        ]}}
        """#.utf8)))
        var live = LiveSessions()
        live.apply(playing("13", state: "playing", offset: 60_000))
        live.seed(statusSessions: root)

        #expect(live.playback.map(\.session) == [.playback("13"), .playback("12")])
        #expect(live.playback.first?.viewOffset == 60_000)
        #expect(live.playback.last?.state == "paused")
        #expect(live.playback.last?.viewOffset == 90_000)
        #expect(live.transcodes.map(\.session) == [.transcode("abc")])
        #expect(live.transcodes.first?.subject == "Streaming")

        live.apply(transcode("update", id: "abc", progress: 9))
        #expect(live.transcodes.count == 1)
        #expect(live.transcodes.first?.progress == 9)
    }
}
