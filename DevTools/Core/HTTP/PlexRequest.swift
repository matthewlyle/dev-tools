import Foundation

struct QueryParam: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var name: String
    var value: String
    var enabled = true
}

struct HeaderField: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var name: String
    var value: String
    var enabled = true
}

enum AcceptFormat: String, Codable, Sendable, CaseIterable, Identifiable {
    case json = "application/json"
    case xml = "application/xml"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .json: "JSON"
        case .xml: "XML"
        }
    }
}

struct PlexRequest: Hashable, Codable, Sendable {
    var path: String
    var query: [QueryParam] = []
    var headers: [HeaderField] = []
    var accept: AcceptFormat = .json

    init(path: String = "/") {
        self.path = path
    }

    var summary: String {
        let enabled = query.filter(\.enabled)
        guard !enabled.isEmpty else { return path }
        let joiner = path.contains("?") ? "&" : "?"
        return path + joiner + enabled.map { "\($0.name)=\($0.value)" }.joined(separator: "&")
    }

    /// Resolves against `base`, merging any query already embedded in `path`
    /// with the enabled `query` params. The token never goes in the URL —
    /// `PlexHTTP` sends it as a header, so it stays out of logs and copies.
    func url(base: URL) -> URL? {
        let (purePath, embedded) = Self.splitPath(path)

        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        components.path = purePath.hasPrefix("/") ? purePath : "/" + purePath

        var items = embedded
        items += query.filter(\.enabled).map { URLQueryItem(name: $0.name, value: $0.value) }
        components.queryItems = items.isEmpty ? nil : items
        return components.url
    }

    /// The request minus any `X-Plex-Token` typed into its path, params, or
    /// headers: the form that's saved, copied, or exported, since a typed
    /// credential would otherwise sit in plain JSON on disk. Sending it falls
    /// back to the server's own token.
    var withoutCredentials: PlexRequest {
        var copy = self
        copy.headers.removeAll { Self.isCredential($0.name) }
        copy.query.removeAll { Self.isCredential($0.name) }
        let (purePath, embedded) = Self.splitPath(path)
        if embedded.contains(where: { Self.isCredential($0.name) }) {
            var components = URLComponents()
            components.queryItems = embedded.filter { !Self.isCredential($0.name) }
            let query = components.percentEncodedQuery ?? ""
            copy.path = query.isEmpty ? purePath : purePath + "?" + query
        }
        return copy
    }

    private static func isCredential(_ name: String) -> Bool {
        name.caseInsensitiveCompare("X-Plex-Token") == .orderedSame
    }

    static func splitPath(_ raw: String) -> (path: String, query: [URLQueryItem]) {
        guard let qIndex = raw.firstIndex(of: "?") else { return (raw, []) }
        let path = String(raw[..<qIndex])
        var components = URLComponents()
        components.percentEncodedQuery = String(raw[raw.index(after: qIndex)...])
        return (path, components.queryItems ?? [])
    }
}
