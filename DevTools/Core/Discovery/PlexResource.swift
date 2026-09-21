import Foundation

/// One entry from `GET https://plex.tv/api/v2/resources`.
struct PlexResource: Sendable, Codable, Hashable, Identifiable {
    var id: String { clientIdentifier }

    let name: String
    let product: String?
    let productVersion: String?
    let platform: String?
    let platformVersion: String?
    let device: String?
    let clientIdentifier: String
    let provides: String
    let owned: Bool
    let ownerId: Int?
    let accessToken: String?
    let publicAddress: String?
    let httpsRequired: Bool?
    let relay: Bool?
    let presence: Bool?
    let sourceTitle: String?
    let connections: [Connection]

    var isServer: Bool {
        provides.split(separator: ",").contains("server")
    }

    /// Avatar of the server's owner for shared servers; owned servers use the
    /// signed-in account's thumb instead.
    var ownerAvatarURL: URL? {
        guard !owned, let ownerId else { return nil }
        return URL(string: "https://plex.tv/users/\(ownerId)/avatar")
    }
}

struct Connection: Sendable, Codable, Hashable, Identifiable {
    var id: String { uri }

    let `protocol`: String
    let address: String
    let port: Int
    let uri: String
    let local: Bool
    let relay: Bool
    let IPv6: Bool

    var url: URL? { URL(string: uri) }
    var isHTTPS: Bool { `protocol` == "https" }

    enum Kind: String, Sendable {
        case local = "Local"
        case remote = "Remote"
        case relay = "Relay"
    }

    var kind: Kind {
        if relay { return .relay }
        return local ? .local : .remote
    }

    /// Lower ranks are preferred: local https, local http, remote https, remote http, relay.
    var rank: Int {
        switch (relay, local, isHTTPS) {
        case (true, _, _): 4
        case (false, true, true): 0
        case (false, true, false): 1
        case (false, false, true): 2
        case (false, false, false): 3
        }
    }
}
