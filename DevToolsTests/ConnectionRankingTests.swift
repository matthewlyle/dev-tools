import Testing
@testable import DevTools

struct ConnectionRankingTests {
    private func connection(protocol: String, local: Bool, relay: Bool) -> Connection {
        Connection(
            protocol: `protocol`,
            address: "10.0.0.1",
            port: 32400,
            uri: "\(`protocol`)://10-0-0-1.example.plex.direct:32400/\(local)/\(relay)",
            local: local,
            relay: relay,
            IPv6: false
        )
    }

    @Test func localHTTPSBeatsEverything() {
        let localHTTPS = connection(protocol: "https", local: true, relay: false)
        let others = [
            connection(protocol: "http", local: true, relay: false),
            connection(protocol: "https", local: false, relay: false),
            connection(protocol: "http", local: false, relay: false),
            connection(protocol: "https", local: false, relay: true),
        ]
        for other in others {
            #expect(localHTTPS.rank < other.rank)
        }
    }

    @Test func anyHTTPSBeatsAnyHTTP() {
        let secure = [
            connection(protocol: "https", local: false, relay: false),
            connection(protocol: "https", local: false, relay: true),
        ]
        let plain = [
            connection(protocol: "http", local: true, relay: false),
            connection(protocol: "http", local: false, relay: false),
        ]
        for s in secure {
            for p in plain {
                #expect(s.rank < p.rank)
            }
        }
    }

    @Test func relayTrailsDirectHTTPS() {
        let relay = connection(protocol: "https", local: true, relay: true)
        #expect(relay.rank > connection(protocol: "https", local: false, relay: false).rank)
    }

    @Test func kindReflectsFlags() {
        #expect(connection(protocol: "https", local: true, relay: false).kind == .local)
        #expect(connection(protocol: "https", local: false, relay: false).kind == .remote)
        #expect(connection(protocol: "https", local: false, relay: true).kind == .relay)
    }
}
