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

enum TokenPlacement: String, Codable, Sendable, CaseIterable, Identifiable {
    case header
    case query

    var id: String { rawValue }

    var label: String {
        switch self {
        case .header: "Header"
        case .query: "Query"
        }
    }
}

/// An editable GET request against a Plex server. Everything the request
/// builder can change lives here; `PlexHTTP` turns it into a `URLRequest`.
struct PlexRequest: Hashable, Codable, Sendable {
    var path: String
    var query: [QueryParam] = []
    var headers: [HeaderField] = []
    var accept: AcceptFormat = .json
    var tokenPlacement: TokenPlacement = .header

    init(path: String = "/") {
        self.path = path
    }

    /// `path` plus enabled params, for compact display.
    var summary: String {
        let enabled = query.filter(\.enabled)
        guard !enabled.isEmpty else { return path }
        let joiner = path.contains("?") ? "&" : "?"
        return path + joiner + enabled.map { "\($0.name)=\($0.value)" }.joined(separator: "&")
    }

    /// Resolves against `base`, merging any query already embedded in `path`
    /// with the enabled `query` params. Returns nil if the result isn't a URL.
    func url(base: URL, token: String?) -> URL? {
        let (purePath, embedded) = Self.splitPath(path)

        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        components.path = purePath.hasPrefix("/") ? purePath : "/" + purePath

        var items = embedded
        items += query.filter(\.enabled).map { URLQueryItem(name: $0.name, value: $0.value) }
        if tokenPlacement == .query, let token {
            items.append(URLQueryItem(name: "X-Plex-Token", value: token))
        }
        components.queryItems = items.isEmpty ? nil : items
        return components.url
    }

    /// Separates `/library/sections?type=1` into `/library/sections` and `[type=1]`.
    static func splitPath(_ raw: String) -> (path: String, query: [URLQueryItem]) {
        guard let qIndex = raw.firstIndex(of: "?") else { return (raw, []) }
        let path = String(raw[..<qIndex])
        var components = URLComponents()
        components.percentEncodedQuery = String(raw[raw.index(after: qIndex)...])
        return (path, components.queryItems ?? [])
    }
}
