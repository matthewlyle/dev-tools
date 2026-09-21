import Foundation

enum LinkDetector {
    enum Link: Hashable {
        case server(path: String)
        case external(URL)
    }

    static let navigableAttributes: Set<String> = [
        "key", "parentKey", "grandparentKey", "librarySectionKey", "hubKey",
        "thumb", "parentThumb", "grandparentThumb",
        "art", "parentArt", "grandparentArt",
        "theme", "parentTheme", "grandparentTheme",
        "composite", "banner",
    ]

    static let imageAttributes: Set<String> = [
        "thumb", "parentThumb", "grandparentThumb",
        "art", "parentArt", "grandparentArt",
        "composite", "banner",
    ]

    static func isNavigable(_ attribute: Attribute) -> Bool {
        navigableAttributes.contains(attribute.name) && !attribute.value.isEmpty
    }

    /// Follows the API's documented rule: the current request path is
    /// treated as having a trailing slash, so `home` under
    /// `/library/sections` resolves to `/library/sections/home`; values that
    /// start with `/` are used as-is; values with a scheme are external.
    static func resolve(_ value: String, relativeTo requestPath: String) -> Link? {
        guard !value.isEmpty else { return nil }
        if value.contains("://") {
            return URL(string: value).map(Link.external)
        }
        if value.hasPrefix("/") {
            return .server(path: value)
        }
        let base = PlexRequest.splitPath(requestPath).path
        let joined = base.hasSuffix("/") ? base + value : base + "/" + value
        return .server(path: joined.hasPrefix("/") ? joined : "/" + joined)
    }

    static func imageURL(for value: String, server: ConnectedServer, height: Int) -> URL? {
        if value.contains("://") { return URL(string: value) }
        var components = URLComponents(url: server.baseURL, resolvingAgainstBaseURL: false)!
        components.path = "/photo/:/transcode"
        components.queryItems = [
            URLQueryItem(name: "url", value: value),
            URLQueryItem(name: "height", value: String(height)),
            URLQueryItem(name: "width", value: String(height)),
            URLQueryItem(name: "minSize", value: "1"),
            URLQueryItem(name: "X-Plex-Token", value: server.accessToken),
        ]
        return components.url
    }
}
