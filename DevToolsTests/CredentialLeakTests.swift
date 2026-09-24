import Foundation
import Testing
@testable import DevTools

struct CredentialLeakTests {
    private let resourceJSON = Data("""
    [{
        "name": "Basement",
        "clientIdentifier": "abc123",
        "provides": "server",
        "owned": true,
        "accessToken": "SECRET-TOKEN-VALUE",
        "httpsRequired": false,
        "connections": [{
            "protocol": "https", "address": "10.0.0.1", "port": 32400,
            "uri": "https://10-0-0-1.abc123.plex.direct:32400",
            "local": true, "relay": false, "IPv6": false
        }]
    }]
    """.utf8)

    @Test func encodedResourceNeverCarriesItsToken() throws {
        let decoded = try JSONDecoder().decode([PlexResource].self, from: resourceJSON)
        #expect(decoded[0].accessToken == "SECRET-TOKEN-VALUE")

        let encoded = try JSONEncoder().encode(decoded)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("SECRET-TOKEN-VALUE"))

        let restored = try JSONDecoder().decode([PlexResource].self, from: encoded)
        #expect(restored[0].accessToken == nil)
        #expect(restored[0].clientIdentifier == "abc123")
        #expect(restored[0].connections == decoded[0].connections)
    }

    @Test func redirectsStayOnTheOrigin() {
        let source = URL(string: "https://10-0-0-1.abc.plex.direct:32400/library")!
        #expect(SameOriginRedirects.allows(from: source, to: URL(string: "https://10-0-0-1.abc.plex.direct:32400/web/index.html")!))
        #expect(!SameOriginRedirects.allows(from: source, to: URL(string: "https://evil.example:32400/library")!))
        #expect(!SameOriginRedirects.allows(from: source, to: URL(string: "https://10-0-0-1.abc.plex.direct:443/library")!))
        #expect(!SameOriginRedirects.allows(from: source, to: URL(string: "http://10-0-0-1.abc.plex.direct:32400/library")!))
    }

    @Test func defaultPortMatchesExplicitPort() {
        #expect(SameOriginRedirects.allows(from: URL(string: "https://plex.tv/api")!, to: URL(string: "https://plex.tv:443/api/v2")!))
    }
}
