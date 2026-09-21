import Foundation
import Testing
@testable import DevTools

struct PlexRequestURLTests {
    private let base = URL(string: "https://server.example.plex.direct:32400")!

    @Test func plainPath() {
        let request = PlexRequest(path: "/library/sections")
        #expect(request.url(base: base, token: nil)?.absoluteString == "https://server.example.plex.direct:32400/library/sections")
    }

    @Test func missingLeadingSlashIsAdded() {
        let request = PlexRequest(path: "identity")
        #expect(request.url(base: base, token: nil)?.path == "/identity")
    }

    @Test func embeddedQueryMergesWithParams() {
        var request = PlexRequest(path: "/library/sections/1/all?type=1")
        request.query = [QueryParam(name: "sort", value: "addedAt:desc")]
        let url = request.url(base: base, token: nil)!
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        #expect(items.map(\.name) == ["type", "sort"])
        #expect(items.map(\.value) == ["1", "addedAt:desc"])
    }

    @Test func disabledParamsAreOmitted() {
        var request = PlexRequest(path: "/x")
        request.query = [
            QueryParam(name: "a", value: "1"),
            QueryParam(name: "b", value: "2", enabled: false),
        ]
        let url = request.url(base: base, token: nil)!
        #expect(url.query == "a=1")
    }

    @Test func tokenInQueryOnlyWhenRequested() {
        var request = PlexRequest(path: "/x")
        #expect(request.url(base: base, token: "tok")?.query == nil)

        request.tokenPlacement = .query
        #expect(request.url(base: base, token: "tok")?.query == "X-Plex-Token=tok")
    }

    @Test func splitPathKeepsPercentEncodedQuery() {
        let (path, items) = PlexRequest.splitPath("/hubs/search?query=hello%20world")
        #expect(path == "/hubs/search")
        #expect(items.first?.name == "query")
        #expect(items.first?.value == "hello world")
    }
}
