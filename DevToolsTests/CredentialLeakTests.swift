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

    @Test func notificationSocketIsEncryptedOrRefused() throws {
        let identity = ClientIdentity(clientIdentifier: "id", product: "p", version: "1", platform: "macOS", platformVersion: "26.0", device: "Mac", deviceName: "Mac")
        func server(_ uri: String) -> ConnectedServer {
            let url = URL(string: uri)!
            let connection = Connection(protocol: url.scheme!, address: "10.0.0.1", port: 32400, uri: uri, local: true, relay: false, IPv6: false)
            return ConnectedServer(machineID: "abc", name: "Basement", baseURL: url, accessToken: "SECRET", connection: connection, owned: true)
        }

        let secure = try NotificationTransport.request(server: server("HTTPS://10-0-0-1.abc.plex.direct:32400"), identity: identity)
        #expect(secure.url?.scheme == "wss")
        #expect(throws: NotificationTransportError.self) {
            try NotificationTransport.request(server: server("http://10.0.0.1:32400"), identity: identity)
        }
    }

    private func redact(_ text: String, known: [String] = []) -> String {
        CredentialRedactor.redact(text, known: known)
    }

    @Test func labelledValuesAreMaskedAndTheRestKept() {
        let json = redact(#"{"MyPlex":{"authToken":"abcdefghijklmnopqrst","username":"matt"}}"#)
        #expect(json == #"{"MyPlex":{"authToken":"••••••••","username":"matt"}}"#)

        let xml = redact(#"<Video token="abcdefghijklmnopqrst" title="Alien"/>"#)
        #expect(xml == #"<Video token="••••••••" title="Alien"/>"#)

        let url = redact(#"{"thumb":"/library/1/thumb?x-plex-token=abcdefghijklmnopqrst&w=1"}"#)
        #expect(url == #"{"thumb":"/library/1/thumb?x-plex-token=••••••••&w=1"}"#)
    }

    @Test func plexOnlineTokenSettingIsMaskedWithoutTouchingItsNeighbours() {
        let json = redact(#"{"Setting":[{"id":"FriendlyName","value":"Basement"},{"id":"PlexOnlineToken","type":"text","value":"onlinetoken123456789","hidden":true},{"value":"Upstairs","id":"Other"}]}"#)
        #expect(!json.contains("onlinetoken123456789"))
        #expect(json.contains(#""value":"Basement""#))
        #expect(json.contains(#""value":"Upstairs""#))

        let xml = redact(#"<Setting id="FriendlyName" value="Basement"/><Setting id="PlexOnlineToken" value="onlinetoken123456789"/><Setting value="reversed1234567890" id="PlexOnlineToken"/>"#)
        #expect(xml == #"<Setting id="FriendlyName" value="Basement"/><Setting id="PlexOnlineToken" value="••••••••"/><Setting value="••••••••" id="PlexOnlineToken"/>"#)
    }

    @Test func aCredentialIsMaskedWhereverItReappears() {
        let labelled = redact(#"{"authToken":"abcdefghijklmnop","note":"sent abcdefghijklmnop"}"#)
        #expect(!labelled.contains("abcdefghijklmnop"))

        let known = redact(#"{"key":"/transcode?session=1&t=KNOWNTOKEN12345"}"#, known: ["KNOWNTOKEN12345"])
        #expect(known == #"{"key":"/transcode?session=1&t=••••••••"}"#)
    }

    @Test func aShortLabelledValueIsMaskedOnlyWhereLabelled() {
        #expect(redact(#"{"token":"abc","title":"abc"}"#) == #"{"token":"••••••••","title":"abc"}"#)
    }

    @Test func responseHeadersAreMaskedAndBinaryBodiesLeftAlone() {
        let token = "KNOWNTOKEN12345"
        let binary = Data([0xFF, 0xD8, 0xFF]) + Data(token.utf8)
        let response = PlexResponse(
            url: URL(string: "https://server.example:32400/x")!,
            status: 302,
            headers: ["Location": "https://elsewhere.example/?X-Plex-Token=\(token)"],
            body: binary,
            duration: .zero,
            receivedAt: .now
        )
        let redacted = CredentialRedactor.redact(response, known: [token])
        #expect(redacted.headers["Location"] == "https://elsewhere.example/?X-Plex-Token=••••••••")
        #expect(redacted.body == binary)
    }
}