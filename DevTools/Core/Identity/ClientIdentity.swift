import Foundation
#if os(iOS)
import UIKit
#endif

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

    @MainActor
    static func current() -> ClientIdentity {
        let defaults = UserDefaults.standard
        // Not "clientIdentifier": plex.tv refuses legacy-token PINs for an
        // identifier that registered a JWT key, which a past build did.
        let key = "plexClientIdentifier"
        let id: String
        if let stored = defaults.string(forKey: key) {
            id = stored
        } else {
            id = UUID().uuidString
            defaults.set(id, forKey: key)
        }

        let os = ProcessInfo.processInfo.operatingSystemVersion
        #if os(macOS)
        let platform = "macOS"
        let device = "Mac"
        let deviceName = Host.current().localizedName ?? "Mac"
        #else
        let platform = "iOS"
        let device = UIDevice.current.userInterfaceIdiom == .phone ? "iPhone" : "iPad"
        let deviceName = device
        #endif
        return ClientIdentity(
            clientIdentifier: id,
            product: "Dev Tools for Plex",
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1",
            platform: platform,
            platformVersion: "\(os.majorVersion).\(os.minorVersion)",
            device: device,
            deviceName: deviceName
        )
    }
}
