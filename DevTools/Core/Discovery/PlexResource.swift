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
