import Foundation
import Testing
@testable import DevTools

struct CurlExporterTests {
    private let base = URL(string: "https://server.example.plex.direct:32400")!

    @Test func tokenIsAPlaceholderNeverTheCredential() {
        var request = PlexRequest(path: "/library/sections")
        request.headers = [HeaderField(name: "X-Plex-Container-Size", value: "50")]
        let command = CurlExporter.command(for: request, base: base, identityHeaders: ["X-Plex-Product": "Plex Dev Tools"])!

        #expect(command.hasPrefix("curl 'https://server.example.plex.direct:32400/library/sections'"))
        #expect(command.contains("-H \"X-Plex-Token: $PLEX_TOKEN\""))
        #expect(command.contains("-H 'Accept: application/json'"))
        #expect(command.contains("-H 'X-Plex-Product: Plex Dev Tools'"))
        #expect(command.contains("-H 'X-Plex-Container-Size: 50'"))
        #expect(!command.contains("Token: ") || command.contains("$PLEX_TOKEN"))
    }

    @Test func disabledHeadersAreOmittedAndQuotesAreEscaped() {
        var request = PlexRequest(path: "/hubs/search?query=it's")
        request.headers = [HeaderField(name: "X-Skip", value: "1", enabled: false)]
        let command = CurlExporter.command(for: request, base: base, identityHeaders: [:])!

        #expect(!command.contains("X-Skip"))
        // The apostrophe is percent-encoded by URLComponents; if it weren't, it would be shell-escaped.
        #expect(command.contains("query=it") && (command.contains("it%27s") || command.contains("it'\\''s")))
    }
}
