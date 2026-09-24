import Foundation

enum CredentialRedactor {
    static let mask = "••••••••"

    static let tokenNames = ["token", "authToken", "accessToken", "authenticationToken", "transientToken", "X-Plex-Token"]

    /// Masking a shorter value everywhere would eat unrelated text, so it's masked only where labelled.
    private static let globalMinimum = 8

    private static let names = tokenNames.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
    private static let query = regex(#"(?i)\bX-Plex-Token=([^&"'\s<>]+)"#)
    private static let jsonKey = regex(#""(?:\#(names))"\s*:\s*"([^"\\]+)""#)
    private static let xmlAttribute = regex(#"\b(?:\#(names))="([^"]+)""#)
    private static let jsonOnlineToken = [
        regex(#""id"\s*:\s*"PlexOnlineToken"[^{}]*?"value"\s*:\s*"([^"\\]+)""#),
        regex(#""value"\s*:\s*"([^"\\]+)"[^{}]*?"id"\s*:\s*"PlexOnlineToken""#),
    ]
    private static let xmlOnlineToken = [
        regex(#"\bid="PlexOnlineToken"[^<>]*?\bvalue="([^"]+)""#),
        regex(#"\bvalue="([^"]+)"[^<>]*?\bid="PlexOnlineToken""#),
    ]

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern)
    }

    /// Scanning a multi-MB body is slow, so a JSON body skips the XML patterns and the reverse.
    private static func patterns(for text: String) -> [NSRegularExpression] {
        let first = text.first { !$0.isWhitespace }
        let online = contains(text, "PlexOnlineToken")
        var patterns = [query]
        if first != "<" {
            patterns.append(jsonKey)
            if online { patterns += jsonOnlineToken }
        }
        if first != "{", first != "[" {
            patterns.append(xmlAttribute)
            if online { patterns += xmlOnlineToken }
        }
        return patterns
    }

    /// `String.contains` and `range(of:)` are far slower than a byte search to miss on a multi-MB string.
    private static func contains(_ text: String, _ needle: String) -> Bool {
        var text = text
        return text.withUTF8 { haystack in
            needle.utf8.withContiguousStorageIfAvailable { needle in
                memmem(haystack.baseAddress, haystack.count, needle.baseAddress, needle.count) != nil
            } ?? false
        }
    }

    static func redact(_ text: String, known: [String]) -> String {
        var secrets = Set(known.filter { $0.count >= globalMinimum })
        var result = text
        // Every token name and `PlexOnlineToken` contain it.
        if contains(text, "oken") {
            let source = text as NSString
            var ranges: [NSRange] = []
            for pattern in patterns(for: text) {
                for match in pattern.matches(in: text, range: NSRange(location: 0, length: source.length)) {
                    let range = match.range(at: 1)
                    ranges.append(range)
                    let value = source.substring(with: range)
                    if value.count >= globalMinimum { secrets.insert(value) }
                }
            }
            let masked = NSMutableString(string: text)
            var floor = Int.max
            for range in ranges.sorted(by: { $0.location > $1.location }) where NSMaxRange(range) <= floor {
                masked.replaceCharacters(in: range, with: mask)
                floor = range.location
            }
            result = masked as String
        }
        secrets.remove(mask)
        for secret in secrets.sorted(by: { $0.count > $1.count }) where contains(result, secret) {
            result = result.replacingOccurrences(of: secret, with: mask)
        }
        return result
    }

    static func redact(_ response: PlexResponse, known: [String]) -> PlexResponse {
        let text = String(data: response.body, encoding: .utf8)
        return PlexResponse(
            url: response.url,
            status: response.status,
            headers: response.headers.mapValues { redact($0, known: known) },
            body: text.map { Data(redact($0, known: known).utf8) } ?? response.body,
            duration: response.duration,
            receivedAt: response.receivedAt
        )
    }
}
