import Foundation

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

    var ownerAvatarURL: URL? {
        guard !owned, let ownerId else { return nil }
        return URL(string: "https://plex.tv/users/\(ownerId)/avatar")
    }

    var hostDescription: String? {
        [device, platform].compactMap { $0 }.first { !$0.isEmpty }
    }

    /// Never encodes `accessToken`: an encoded resource is what lands on
    /// disk, and no credential is written outside the Keychain. The token
    /// comes back with the next `/api/v2/resources` refresh.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(product, forKey: .product)
        try container.encodeIfPresent(productVersion, forKey: .productVersion)
        try container.encodeIfPresent(platform, forKey: .platform)
        try container.encodeIfPresent(platformVersion, forKey: .platformVersion)
        try container.encodeIfPresent(device, forKey: .device)
        try container.encode(clientIdentifier, forKey: .clientIdentifier)
        try container.encode(provides, forKey: .provides)
        try container.encode(owned, forKey: .owned)
        try container.encodeIfPresent(ownerId, forKey: .ownerId)
        try container.encodeIfPresent(publicAddress, forKey: .publicAddress)
        try container.encodeIfPresent(httpsRequired, forKey: .httpsRequired)
        try container.encodeIfPresent(relay, forKey: .relay)
        try container.encodeIfPresent(presence, forKey: .presence)
        try container.encodeIfPresent(sourceTitle, forKey: .sourceTitle)
        try container.encode(connections, forKey: .connections)
    }

    enum HostMark: Sendable, Hashable {
        case symbol(String)
        case asset(String)
    }

    var hostMark: HostMark {
        let device = (device ?? "").lowercased()
        if device.contains("docker") || device.contains("container") { return .asset("host-docker") }
        if device.contains("synology") { return .asset("host-synology") }
        if device.contains("qnap") { return .asset("host-qnap") }
        if device.contains("unraid") { return .asset("host-unraid") }
        switch (platform ?? "").lowercased() {
        case let p where p.contains("windows"): return .asset("host-windows")
        case let p where p.contains("mac") || p.contains("osx") || p.contains("darwin"): return .symbol("apple.logo")
        case let p where p.contains("linux"): return .asset("host-linux")
        case let p where p.contains("freebsd") || p.contains("bsd"): return .asset("host-freebsd")
        case let p where p.contains("android"): return .asset("host-android")
        default: return .symbol("server.rack")
        }
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

    /// Every HTTPS connection before any plain HTTP one, relay included:
    /// over HTTP the token crosses the network in the clear. Within each,
    /// local first; relay trails direct HTTPS for its bandwidth cap.
    var rank: Int {
        switch (isHTTPS, relay, local) {
        case (true, false, true): 0
        case (true, false, false): 1
        case (true, true, _): 2
        case (false, _, true): 3
        case (false, _, false): 4
        }
    }
}
