import Foundation

/// Masks credentials in text a server sent, before anything shows, copies,
/// or parses it; there is deliberately no way to reveal them. A value is a
/// credential when it's filed under a token name (a JSON key, an XML
/// attribute, an `X-Plex-Token` query item, the `PlexOnlineToken` setting)
/// or is a token the app already holds. A credential long enough to be
/// unambiguous is then masked everywhere, so it can't sit unlabelled in a
/// URL further down.
enum CredentialRedactor {
    static let mask = "••••••••"

    static let tokenNames = ["token", "authToken", "accessToken", "authenticationToken", "transientToken", "X-Plex-Token"]

    /// Shorter values are masked only where they're labelled: replacing a
    /// short string everywhere would eat unrelated text.
    private static let globalMinimum = 8

    /// Capture group 1 is the credential.
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

    /// Each scan of a multi-MB body costs tens of milliseconds, so a JSON
    /// body skips the XML patterns and the reverse; text that's neither
    /// gets all of them.
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

    /// `String.contains` and Foundation's `range(of:)` both take hundreds of
    /// milliseconds to miss on a multi-MB string; a byte search takes a few.
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

    /// Bodies that aren't UTF-8 (images, binary) pass through untouched.
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
