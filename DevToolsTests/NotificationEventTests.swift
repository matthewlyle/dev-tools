import Foundation
import Testing
@testable import DevTools

struct NotificationEventTests {
    private func metadata(_ item: String) throws -> Node {
        try #require(JSONNodeParser.parse(Data(#"{"MediaContainer":{"size":1,"Metadata":[\#(item)]}}"#.utf8)))
    }

    @Test func playingSessionIsLookedUpByRatingKey() throws {
        let event = NotificationEvent.make(raw: #"""
        {"NotificationContainer":{"type":"playing","size":1,"PlaySessionStateNotification":[
          {"sessionKey":"12","clientIdentifier":"abc","key":"/library/metadata/28282","ratingKey":"28282","viewOffset":754000,"state":"playing"}
        ]}}
        """#)
        #expect(event.type == "playing")
        #expect(event.ratingKey == "28282")
        #expect(event.titleKey == "28282")
        #expect(event.state == "playing")
        #expect(event.viewOffset == 754_000)
        #expect(event.summary.hasPrefix("Playing · /library/metadata/28282 · "))
        #expect(event.summary(title: "The Office — S2 E2 · Diversity Day").hasPrefix("Playing · The Office — S2 E2 · Diversity Day · "))
    }

    @Test func untitledTimelineEntryIsLookedUpByItemID() {
        let event = NotificationEvent.make(raw: #"""
        {"NotificationContainer":{"type":"timeline","size":1,"TimelineEntry":[
          {"identifier":"com.plexapp.plugins.library","sectionID":"1","itemID":"28282","type":1,"title":"","state":5}
        ]}}
        """#)
        #expect(event.ratingKey == "28282")
        #expect(event.titleKey == "28282")
        #expect(event.state == "5")
        #expect(event.viewOffset == nil)
        #expect(event.summary == "state 5 · itemID 28282")
        #expect(event.summary(title: "Heat (1995)") == "state 5 · Heat (1995)")
    }

    @Test func payloadTitlesNeedNoLookup() {
        let timeline = NotificationEvent.make(raw: #"""
        {"NotificationContainer":{"type":"timeline","TimelineEntry":[{"itemID":"28282","title":"Heat","state":5}]}}
        """#)
        #expect(timeline.ratingKey == "28282")
        #expect(timeline.titleKey == nil)
        #expect(timeline.summary == "state 5 · Heat")

        let activity = NotificationEvent.make(raw: #"""
        {"NotificationContainer":{"type":"activity","size":1,"ActivityNotification":[
          {"event":"updated","uuid":"u1","Activity":{"uuid":"u1","type":"library.update.section","title":"Scanning Movies","subtitle":"Heat","progress":45}}
        ]}}
        """#)
        #expect(activity.titleKey == nil)
        #expect(activity.summary == "Updated · Scanning Movies · Heat · 45%")
    }

    @Test func ratingKeyIsDigitsFromTheFirstSourcePresent() {
        let keyOnly = NotificationEvent.make(raw: #"""
        {"NotificationContainer":{"type":"playing","PlaySessionStateNotification":[{"key":"/library/metadata/77/children","state":"paused"}]}}
        """#)
        #expect(keyOnly.ratingKey == "77")

        let hostile = NotificationEvent.make(raw: #"""
        {"NotificationContainer":{"type":"playing","PlaySessionStateNotification":[{"ratingKey":"../../accounts","state":"paused"}]}}
        """#)
        #expect(hostile.ratingKey == nil)
        #expect(hostile.titleKey == nil)

        let transcode = NotificationEvent.make(raw: #"""
        {"NotificationContainer":{"type":"transcodeSession.update","TranscodeSession":[{"key":"/transcode/sessions/x","progress":12.6}]}}
        """#)
        #expect(transcode.ratingKey == nil)
        #expect(transcode.summary == "/transcode/sessions/x · 13%")
    }

    @Test func episodeTitleIsShowCodeAndTitle() throws {
        let full = try metadata(#"{"type":"episode","title":"Diversity Day","grandparentTitle":"The Office","parentIndex":2,"index":2}"#)
        #expect(NotificationEvent.itemTitle(metadata: full) == "The Office — S2 E2 · Diversity Day")
        let bare = try metadata(#"{"type":"episode","title":"Pilot","index":1}"#)
        #expect(NotificationEvent.itemTitle(metadata: bare) == "E1 · Pilot")
    }

    @Test func movieTitleCarriesItsYear() throws {
        #expect(NotificationEvent.itemTitle(metadata: try metadata(#"{"type":"movie","title":"Heat","year":1995}"#)) == "Heat (1995)")
        #expect(NotificationEvent.itemTitle(metadata: try metadata(#"{"type":"movie","title":"Heat"}"#)) == "Heat")
    }

    @Test func trackTitleLeadsWithItsArtist() throws {
        let album = try metadata(#"{"type":"track","title":"Reckoner","grandparentTitle":"Radiohead","parentTitle":"In Rainbows"}"#)
        #expect(NotificationEvent.itemTitle(metadata: album) == "Radiohead — Reckoner")
        let compilation = try metadata(#"{"type":"track","title":"Roads","originalTitle":"Portishead","grandparentTitle":"Various Artists"}"#)
        #expect(NotificationEvent.itemTitle(metadata: compilation) == "Portishead — Roads")
    }

    @Test func otherTypesUseTheirTitle() throws {
        #expect(NotificationEvent.itemTitle(metadata: try metadata(#"{"type":"show","title":"The Office","year":2005}"#)) == "The Office")
        #expect(NotificationEvent.itemTitle(metadata: try metadata(#"{"type":"movie","title":""}"#)) == nil)
    }
}
