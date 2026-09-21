import Foundation
import SwiftUI
import Testing
@testable import DevTools

struct MediaItemTests {
    private func item(_ json: String) throws -> MediaItem {
        let root = try #require(JSONNodeParser.parse(Data(json.utf8)))
        return MediaItem(node: try #require(root.children.first))
    }

    @Test func shapeFollowsType() throws {
        #expect(try item(#"{"MediaContainer":{"Metadata":[{"type":"movie","title":"Heat"}]}}"#).shape == .poster)
        #expect(try item(#"{"MediaContainer":{"Metadata":[{"type":"episode","title":"Pilot"}]}}"#).shape == .wide)
        #expect(try item(#"{"MediaContainer":{"Metadata":[{"type":"album","title":"OK"}]}}"#).shape == .square)
        #expect(try item(#"{"MediaContainer":{"Metadata":[{"title":"Untyped"}]}}"#).shape == .poster)
    }

    @Test func movieSubtitleIsYearRatingRuntimeStars() throws {
        let heat = try item(#"{"MediaContainer":{"Metadata":[{"type":"movie","title":"Heat","year":1995,"contentRating":"R","duration":10200000,"rating":8.4}]}}"#)
        let subtitle = try #require(heat.subtitle)
        #expect(subtitle.hasPrefix("1995 · R · "))
        #expect(subtitle.hasSuffix("★ 8.4"))
    }

    @Test func episodeSubtitleLeadsWithSeasonEpisodeCode() throws {
        let ep = try item(#"{"MediaContainer":{"Metadata":[{"type":"episode","title":"1:23:45","index":1,"parentIndex":1,"grandparentTitle":"Chernobyl"}]}}"#)
        #expect(ep.subtitle == "S1·E1 · Chernobyl")
    }

    @Test func thumbFallsBackThroughParentArt() throws {
        let track = try item(#"{"MediaContainer":{"Metadata":[{"type":"track","title":"Reckoner","parentThumb":"/library/metadata/9/thumb/1"}]}}"#)
        #expect(track.thumb == "/library/metadata/9/thumb/1")
        let bare = try item(#"{"MediaContainer":{"Metadata":[{"title":"none"}]}}"#)
        #expect(bare.thumb == nil)
    }

    @Test func tagGroupsAndElementGroupsAreSeparated() throws {
        let movie = try item("""
        {"MediaContainer":{"Metadata":[{"type":"movie","title":"Heat",
          "Genre":[{"tag":"Crime"},{"tag":"Thriller"}],
          "Director":[{"tag":"Michael Mann"}],
          "Media":[{"id":1,"bitrate":12000,"Part":[{"id":2,"size":15000000000}]}]
        }]}}
        """)
        #expect(movie.tagGroups.map(\.name) == ["Genre", "Director"])
        #expect(movie.tagGroups[0].tags == ["Crime", "Thriller"])
        #expect(movie.elementGroups.map(\.name) == ["Media"])
        #expect(movie.elementGroups[0].nodes[0].children.first?.name == "Part")
    }

    @Test func valueDisplayDecodesUnitsByName() {
        #expect(MediaValue.display(name: "size", value: "15000000000")?.contains("GB") == true)
        #expect(MediaValue.display(name: "bitrate", value: "12000") == "12.0 Mbps")
        #expect(MediaValue.display(name: "bitrate", value: "320") == "320 kbps")
        #expect(MediaValue.display(name: "addedAt", value: "1700000000") != nil)
        #expect(MediaValue.display(name: "originallyAvailableAt", value: "1957-04-10") == nil)
        #expect(MediaValue.display(name: "title", value: "Heat") == nil)
        #expect(MediaValue.runtime("5781856") != nil)
        #expect(MediaValue.runtime("500") == nil)
    }

    @Test func ultraBlurHexParsesSixDigitsWithOrWithoutHash() {
        #expect(Color(plexHex: "1a2b3c") != nil)
        #expect(Color(plexHex: "#1A2B3C") != nil)
        #expect(Color(plexHex: "1a2b3") == nil)
        #expect(Color(plexHex: "zzzzzz") == nil)
    }
}
