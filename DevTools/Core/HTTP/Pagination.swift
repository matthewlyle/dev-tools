import Foundation

/// Paging state of a response, per the API's pagination contract: the
/// `X-Plex-Container-Start` / `X-Plex-Container-Total-Size` headers, falling
/// back to `offset` / `size` / `totalSize` on the `MediaContainer`.
struct PaginationInfo: Hashable, Sendable {
    let start: Int
    let size: Int
    let total: Int

    /// The page a listing asks for when none is set: a Media run, and a
    /// media-query endpoint opened from the catalog.
    static let defaultPageSize = 100

    init?(response: PlexResponse, root: Node?) {
        func header(_ name: String) -> Int? {
            response.headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }.flatMap { Int($0.value) }
        }
        guard let total = header("X-Plex-Container-Total-Size") ?? root?["totalSize"].flatMap(Int.init) else { return nil }
        self.total = total
        self.start = header("X-Plex-Container-Start") ?? root?["offset"].flatMap(Int.init) ?? 0
        self.size = root?["size"].flatMap(Int.init) ?? root?.children.count ?? 0
    }

    var end: Int { min(start + size, total) }
    var hasPrevious: Bool { start > 0 }
    var hasNext: Bool { end < total }

    var pageSize: Int { size > 0 ? size : Self.defaultPageSize }

    var label: String {
        if size == 0 { return "0 of \(total.formatted())" }
        return "\((start + 1).formatted())–\(end.formatted()) of \(total.formatted())"
    }
}

extension PlexRequest {
    /// Starts the request on its first page, or with no paging at all.
    /// Either way paging left from an earlier request goes: it would
    /// otherwise quietly page whatever is opened next.
    mutating func resetPaging(firstPage: Bool) {
        let names: Set<String> = ["x-plex-container-start", "x-plex-container-size", "x-plex-container-focus-key"]
        headers.removeAll { names.contains($0.name.lowercased()) }
        if firstPage {
            headers.append(HeaderField(name: "X-Plex-Container-Start", value: "0"))
            headers.append(HeaderField(name: "X-Plex-Container-Size", value: String(PaginationInfo.defaultPageSize)))
        }
    }
}