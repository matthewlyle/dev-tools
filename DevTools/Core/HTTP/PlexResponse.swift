import Foundation

/// The raw outcome of one request. Bytes are the source of truth; every view
/// derives from `body` + `contentType`.
struct PlexResponse: Sendable, Hashable {
    let url: URL
    let status: Int
    let headers: [String: String]
    let body: Data
    let duration: Duration
    let receivedAt: Date

    var contentType: String? {
        headers.first { $0.key.caseInsensitiveCompare("Content-Type") == .orderedSame }?.value
    }

    var isJSON: Bool { contentType?.localizedCaseInsensitiveContains("json") ?? false }
    var isXML: Bool { contentType?.localizedCaseInsensitiveContains("xml") ?? false }

    var byteCount: Int { body.count }

    var bodyText: String { String(decoding: body, as: UTF8.self) }
}
