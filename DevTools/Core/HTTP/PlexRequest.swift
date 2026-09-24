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

    func url(base: URL) -> URL? {
        let (purePath, embedded) = Self.splitPath(path)

        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        components.path = purePath.hasPrefix("/") ? purePath : "/" + purePath

        var items = embedded
        items += query.filter(\.enabled).map { URLQueryItem(name: $0.name, value: $0.value) }
        components.queryItems = items.isEmpty ? nil : items
        return components.url
    }

    var withoutCredentials: PlexRequest {
        var copy = self
        copy.headers.removeAll { Self.isCredential($0.name) }
        copy.query.removeAll { Self.isCredential($0.name) }
        copy.path = Self.withoutCredentials(path)
        return copy
    }

    static func withoutCredentials(_ path: String) -> String {
        let (purePath, embedded) = splitPath(path)
        guard embedded.contains(where: { isCredential($0.name) }) else { return path }
        var components = URLComponents()
        components.queryItems = embedded.filter { !isCredential($0.name) }
        let query = components.percentEncodedQuery ?? ""
        return query.isEmpty ? purePath : purePath + "?" + query
    }

    private static func isCredential(_ name: String) -> Bool {
        name.caseInsensitiveCompare("X-Plex-Token") == .orderedSame
    }

    static func splitPath(_ raw: String) -> (path: String, query: [URLQueryItem]) {
        guard let qIndex = raw.firstIndex(of: "?") else { return (raw, []) }
        let path = String(raw[..<qIndex])
        let query = validlyEncoded(raw[raw.index(after: qIndex)...])
        return (path, URLComponents(string: "?" + query)?.queryItems ?? [])
    }

    private static func validlyEncoded(_ query: Substring) -> String {
        let scalars = Array(query.unicodeScalars)
        var out = ""
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "%", index + 2 < scalars.count,
               scalars[index + 1].properties.isASCIIHexDigit, scalars[index + 2].properties.isASCIIHexDigit {
                out.unicodeScalars.append(contentsOf: scalars[index...index + 2])
                index += 3
                continue
            }
            if CharacterSet.urlQueryAllowed.contains(scalar) {
                out.unicodeScalars.append(scalar)
            } else {
                out += String(scalar).addingPercentEncoding(withAllowedCharacters: CharacterSet()) ?? ""
            }
            index += 1
        }
        return out
    }
}
