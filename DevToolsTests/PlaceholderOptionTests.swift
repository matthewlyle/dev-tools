import Foundation
import Testing
@testable import DevTools

struct PlaceholderOptionTests {
    private func root(_ json: String) throws -> Node {
        try #require(JSONNodeParser.parse(Data(json.utf8)))
    }

    @Test func libraryItemsUseRatingKeyAndTitle() throws {
        let node = try root("""
        {"MediaContainer":{"Metadata":[
          {"ratingKey":"42","title":"Road Trip","type":"playlist"},
          {"ratingKey":"43","type":"playlist"},
          {"title":"no key"}
        ]}}
        """)
        let options = RequestStore.itemOptions(from: node)
        #expect(options.map(\.key) == ["42", "43"])
        #expect(options.map(\.title) == ["Road Trip", "43"])
        #expect(options.allSatisfy { $0.group == nil })
    }

    @Test func collectionsCarryTheirLibraryAsGroup() throws {
        let node = try root("""
        {"MediaContainer":{"Metadata":[{"ratingKey":"7","title":"Marvel"}]}}
        """)
        let options = RequestStore.itemOptions(from: node, group: "Movies")
        #expect(options == [RequestStore.PlaceholderOption(key: "7", title: "Marvel", group: "Movies")])
    }

    @Test func devicesFallBackThroughIdAndNameAttributes() throws {
        let node = try root("""
        {"MediaContainer":{"Device":[
          {"key":"dev-1","title":"Living Room HDHomeRun"},
          {"uuid":"dev-2","make":"SiliconDust","model":"HDHR5-4US"},
          {"id":"dev-3"},
          {"make":"nameless"}
        ]}}
        """)
        let options = RequestStore.deviceOptions(from: node)
        #expect(options.map(\.key) == ["dev-1", "dev-2", "dev-3"])
        #expect(options.map(\.title) == ["Living Room HDHomeRun", "SiliconDust HDHR5-4US", "dev-3"])
    }

    @Test func listablePlaceholdersIncludeSectionsFirst() {
        #expect(RequestStore.listablePlaceholders.first == "sectionId")
        #expect(RequestStore.listablePlaceholders.contains("playlistId"))
        #expect(RequestStore.listablePlaceholders.contains("collectionId"))
        #expect(RequestStore.listablePlaceholders.contains("deviceId"))
    }
}
