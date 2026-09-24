import Foundation
import Testing
@testable import DevTools

struct PlexRequestURLTests {
    private let base = URL(string: "https://server.example.plex.direct:32400")!

    @Test func plainPath() {
        let request = PlexRequest(path: "/library/sections")
        #expect(request.url(base: base)?.absoluteString == "https://server.example.plex.direct:32400/library/sections")
    }

    @Test func missingLeadingSlashIsAdded() {
        let request = PlexRequest(path: "identity")
        #expect(request.url(base: base)?.path == "/identity")
    }

    @Test func embeddedQueryMergesWithParams() {
        var request = PlexRequest(path: "/library/sections/1/all?type=1")
        request.query = [QueryParam(name: "sort", value: "addedAt:desc")]
        let url = request.url(base: base)!
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
        let url = request.url(base: base)!
        #expect(url.query == "a=1")
    }

    @Test func tokenNeverAppearsInURL() {
        var request = PlexRequest(path: "/x")
        #expect(request.url(base: base)?.query == nil)

        request.path = "/x?X-Plex-Token=typed"
        #expect(request.url(base: base)?.query == "X-Plex-Token=typed")
    }

    @Test func withoutCredentialsDropsTypedTokensAndKeepsTheRest() {
        var request = PlexRequest(path: "/library/sections?x-plex-token=typed&type=1")
        request.query = [QueryParam(name: "X-Plex-Token", value: "typed"), QueryParam(name: "sort", value: "title")]
        request.headers = [HeaderField(name: "x-plex-token", value: "typed"), HeaderField(name: "X-Plex-Container-Size", value: "50")]

        let stripped = request.withoutCredentials
        #expect(stripped.path == "/library/sections?type=1")
        #expect(stripped.query.map(\.name) == ["sort"])
        #expect(stripped.headers.map(\.name) == ["X-Plex-Container-Size"])
        #expect(!(stripped.url(base: base)?.absoluteString.contains("typed") ?? true))

        #expect(PlexRequest(path: "/x?X-Plex-Token=typed").withoutCredentials.path == "/x")
    }

    @Test func splitPathKeepsPercentEncodedQuery() {
        let (path, items) = PlexRequest.splitPath("/hubs/search?query=hello%20world")
        #expect(path == "/hubs/search")
        #expect(items.first?.name == "query")
        #expect(items.first?.value == "hello world")
    }
}
