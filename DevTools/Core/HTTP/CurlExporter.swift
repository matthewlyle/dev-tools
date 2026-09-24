import Foundation

/// `$PLEX_TOKEN` is double-quoted, unlike every other value, so the shell expands it.
enum CurlExporter {
    static let tokenPlaceholder = "$PLEX_TOKEN"

    static func command(for request: PlexRequest, base: URL, identityHeaders: [String: String]) -> String? {
        let request = request.withoutCredentials
        guard let url = request.url(base: base) else { return nil }
        var lines = ["curl \(quote(url.absoluteString))"]
        lines.append("-H \(quote("Accept: \(request.accept.rawValue)"))")
        lines.append("-H \"X-Plex-Token: \(tokenPlaceholder)\"")
        for (name, value) in identityHeaders.sorted(by: { $0.key < $1.key }) {
            lines.append("-H \(quote("\(name): \(value)"))")
        }
        for header in request.headers where header.enabled && !header.name.isEmpty {
            lines.append("-H \(quote("\(header.name): \(header.value)"))")
        }
        return lines.joined(separator: " \\\n  ")
    }

    private static func quote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
