import Foundation

/// Paging state of a response, per the API's pagination contract: the
/// `X-Plex-Container-Start` / `X-Plex-Container-Total-Size` headers, falling
/// back to `offset` / `size` / `totalSize` on the `MediaContainer`.
struct PaginationInfo: Hashable, Sendable {
    let start: Int
    let size: Int
    let total: Int

    static let defaultPageSize = 50

    init?(response: PlexResponse, root: Node?) {
        func header(_ name: String) -> Int? {
            response.headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }.flatMap { Int($0.value) }
        }
        guard let total = header("X-Plex-Container-Total-Size") ?? root?["totalSize"].flatMap(Int.init) else { return nil }
        self.total = total
        self.start = header("X-Plex-Container-Start") ?? root?["offset"].flatMap(Int.init) ?? 0
        self.size = root?["size"].flatMap(Int.init) ?? root?.children.count ?? 0
    }

    /// Exclusive end index.
    var end: Int { min(start + size, total) }
    var hasPrevious: Bool { start > 0 }
    var hasNext: Bool { end < total }

    /// Page size to keep using; a count-only response (size 0) gets the default.
    var pageSize: Int { size > 0 ? size : Self.defaultPageSize }

    var label: String {
        if size == 0 { return "0 of \(total.formatted())" }
        return "\((start + 1).formatted())–\(end.formatted()) of \(total.formatted())"
    }
}
