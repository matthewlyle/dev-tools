import Foundation
import Testing
@testable import DevTools

@MainActor
struct ValueMemoryTests {
    private let library = """
    {"MediaContainer":{"size":2,"Metadata":[
      {"ratingKey":"101","key":"/library/metadata/101","title":"Alien","librarySectionID":"1",
       "Media":[{"id":"501","Part":[{"id":"601","Stream":[{"id":"701"}]}]}]},
      {"ratingKey":"102","key":"/library/metadata/102","title":"Heat","librarySectionID":"1"}
    ]}}
    """
    private let sections = """
    {"MediaContainer":{"size":2,"Directory":[{"key":"1","title":"Movies"},{"key":"2","title":"Shows"}]}}
    """
    private let devices = """
    {"MediaContainer":{"size":1,"Device":[{"id":"9","title":"HDHomeRun","uuid":"abc"}]}}
    """

    private func memory() -> ValueMemory {
        let memory = ValueMemory()
        for json in [library, sections, devices] {
            memory.record(root: JSONNodeParser.parse(Data(json.utf8))!, serverID: "s")
        }
        return memory
    }

    @Test func metadataPlaceholdersOfferOnlyRatingKeys() {
        let all = memory().candidates(for: "metadataId", serverID: "s")
        #expect(all.map(\.value) == ["101", "102"])
        #expect(memory().candidates(for: "ids", serverID: "s").first?.title == "Alien")
    }

    @Test func sectionPlaceholderMatchesDirectoryKeysAndLibrarySectionIDs() {
        let values = Set(memory().candidates(for: "sectionId", serverID: "s").prefix(3).map(\.value))
        #expect(values == ["1", "2"])
    }

    @Test func elementNamedPlaceholdersMatchByStemOnly() {
        #expect(memory().candidates(for: "deviceId", serverID: "s").map(\.value) == ["9"])
        #expect(memory().candidates(for: "partId", serverID: "s").map(\.value) == ["601"])
        #expect(memory().candidates(for: "streamId", serverID: "s").map(\.value) == ["701"])
        #expect(memory().candidates(for: "playlistId", serverID: "s").isEmpty)
    }

    @Test func nonIdentifiersAreNotRecorded() {
        let all = memory().seen["s"] ?? []
        #expect(!all.contains { $0.attribute == "title" || $0.attribute == "uuid" })
        #expect(!all.contains { $0.attribute == "key" && $0.value.hasPrefix("/") })
    }

    @Test func serversAreIsolatedAndDuplicatesCollapse() {
        let memory = memory()
        memory.record(root: JSONNodeParser.parse(Data(sections.utf8))!, serverID: "s")
        #expect(memory.candidates(for: "sectionId", serverID: "other").isEmpty)
        #expect((memory.seen["s"] ?? []).filter { $0.attribute == "key" && $0.value == "1" }.count == 1)
    }
}
