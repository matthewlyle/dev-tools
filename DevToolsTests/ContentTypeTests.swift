import Testing
@testable import DevTools

struct ContentTypeTests {
    @Test func mediaTypeDropsParameters() {
        #expect(ResponseStatusBar.mediaType("application/json; charset=utf-8") == "application/json")
        #expect(ResponseStatusBar.mediaType("text/xml;charset=utf-8") == "text/xml")
        #expect(ResponseStatusBar.mediaType("  ; charset=utf-8") == nil)
    }

    @Test func subtypeIsTheTokenAfterTheSlash() {
        #expect(ResponseStatusBar.subtype(of: "application/json; charset=utf-8") == "json")
        #expect(ResponseStatusBar.subtype(of: "image/jpeg") == "jpeg")
    }

    @Test func structuredSuffixWinsOverVendorTree() {
        #expect(ResponseStatusBar.subtype(of: "application/vnd.api+json") == "json")
    }

    @Test func malformedTypesHaveNoSubtype() {
        #expect(ResponseStatusBar.subtype(of: "json") == nil)
        #expect(ResponseStatusBar.subtype(of: "application/") == nil)
    }
}
