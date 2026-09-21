import Foundation

/// The `X-Plex-*` headers that identify this app to plex.tv and to servers.
/// `clientIdentifier` is persisted so plex.tv sees one stable device across launches.
struct ClientIdentity: Sendable, Hashable {
    let clientIdentifier: String
    let product: String
    let version: String
    let platform: String
    let platformVersion: String
    let device: String
    let deviceName: String

    var headers: [String: String] {
        [
            "X-Plex-Client-Identifier": clientIdentifier,
            "X-Plex-Product": product,
            "X-Plex-Version": version,
            "X-Plex-Platform": platform,
            "X-Plex-Platform-Version": platformVersion,
            "X-Plex-Device": device,
            "X-Plex-Device-Name": deviceName,
            "X-Plex-Provides": "controller",
        ]
    }

    static func current() -> ClientIdentity {
        let defaults = UserDefaults.standard
        let key = "clientIdentifier"
        let id: String
        if let stored = defaults.string(forKey: key) {
            id = stored
        } else {
            id = UUID().uuidString
            defaults.set(id, forKey: key)
        }

        let os = ProcessInfo.processInfo.operatingSystemVersion
        return ClientIdentity(
            clientIdentifier: id,
            product: "Plex Dev Tools",
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1",
            platform: "macOS",
            platformVersion: "\(os.majorVersion).\(os.minorVersion)",
            device: "Mac",
            deviceName: Host.current().localizedName ?? "Mac"
        )
    }
}
