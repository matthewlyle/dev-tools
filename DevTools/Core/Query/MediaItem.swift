import Foundation

/// One item of a media container as a person reads it: title, artwork,
/// aspect, and a one-line summary of the metadata that matters for its type.
struct MediaItem: Identifiable, Hashable, Sendable {
    enum Shape: Sendable { case poster, square, wide }

    let node: Node

    var id: Int { node.id }
    var title: String { node.headline }
    var type: String? { node["type"] }
    var ratingKey: String? { node["ratingKey"] }
    var summary: String? { node["summary"].flatMap { $0.isEmpty ? nil : $0 } }
    var tagline: String? { node["tagline"].flatMap { $0.isEmpty ? nil : $0 } }

    var thumb: String? {
        for key in ["thumb", "parentThumb", "grandparentThumb", "composite"] {
            if let value = node[key], !value.isEmpty { return value }
        }
        return nil
    }

    var shape: Shape {
        switch type {
        case "episode", "clip", "trailer": .wide
        case "artist", "album", "track", "playlist", "photo", "photoalbum": .square
        default: .poster
        }
    }

    var subtitle: String? {
        let parts: [String?] = switch type {
        case "episode":
            [episodeCode, node["grandparentTitle"], MediaValue.runtime(node["duration"])]
        case "season":
            [node["parentTitle"], MediaValue.count(node["leafCount"], "episode", "episodes")]
        case "show":
            [node["year"], MediaValue.count(node["leafCount"], "episode", "episodes")]
        case "track":
            [node["grandparentTitle"], MediaValue.runtime(node["duration"])]
        case "album":
            [node["parentTitle"], node["year"]]
        case "artist":
            [MediaValue.count(node["childCount"], "album", "albums")]
        case "collection":
            [MediaValue.count(node["childCount"], "item", "items")]
        default:
            [node["year"], node["contentRating"], MediaValue.runtime(node["duration"]), MediaValue.rating(node["rating"] ?? node["audienceRating"])]
        }
        let present = parts.compactMap { $0 }.filter { !$0.isEmpty }
        return present.isEmpty ? nil : present.joined(separator: " · ")
    }

    /// The one line under a poster: the value the results are sorted by, so
    /// a grid sorted by duration reads as durations and one sorted by title
    /// as titles. Falls back to the title when the sort has nothing to show
    /// (`random`, or a field the item lacks).
    func caption(sortedBy key: String?) -> String {
        guard let key, key != "title", key != "titleSort", let resolved = sortValue(key) else { return title }
        switch resolved.name {
        case "rating", "audienceRating", "userRating": return MediaValue.rating(resolved.value) ?? resolved.value
        case "viewCount": return MediaValue.count(resolved.value, "play", "plays") ?? resolved.value
        default: return MediaValue.display(name: resolved.name, value: resolved.value) ?? resolved.value
        }
    }

    /// `media…` sort keys (`mediaBitrate`, `mediaHeight`) live on the
    /// `Media` child, not the item.
    private func sortValue(_ key: String) -> (name: String, value: String)? {
        if let value = node[key], !value.isEmpty { return (key, value) }
        if key.hasPrefix("media"), key.count > 5 {
            let inner = key.dropFirst(5)
            let name = inner.prefix(1).lowercased() + inner.dropFirst()
            if let media = node.children.first(where: { $0.name == "Media" }), let value = media[name], !value.isEmpty {
                return (name, value)
            }
        }
        return nil
    }

    private var episodeCode: String? {
        guard let episode = node["index"] else { return nil }
        if let season = node["parentIndex"] { return "S\(season)·E\(episode)" }
        return "Episode \(episode)"
    }

    /// Child groups whose members are all tags (`Genre`, `Director`, `Role`…).
    var tagGroups: [(name: String, tags: [String])] {
        childGroups.compactMap { group in
            let tags = group.nodes.compactMap { $0["tag"] }
            return tags.count == group.nodes.count && !tags.isEmpty ? (group.name, tags) : nil
        }
    }

    /// Remaining child groups (`Media`, `Guid`, `Image`…), shown as details.
    var elementGroups: [(name: String, nodes: [Node])] {
        childGroups.filter { group in
            !group.nodes.allSatisfy { $0["tag"] != nil } || group.nodes.isEmpty
        }
    }

    private var childGroups: [(name: String, nodes: [Node])] {
        var order: [String] = []
        var buckets: [String: [Node]] = [:]
        for child in node.children {
            if buckets[child.name] == nil { order.append(child.name) }
            buckets[child.name, default: []].append(child)
        }
        return order.map { ($0, buckets[$0]!) }
    }
}

/// Human formatting for attribute values whose names give away their unit.
enum MediaValue {
    static func display(name: String, value: String) -> String? {
        if name == "type" || name == "metadataType", let label = MetadataType.label(value) {
            return label
        }
        if name.hasSuffix("At"), name != "originallyAvailableAt", let epoch = TimeInterval(value), epoch > 1_000_000_000 {
            return Date(timeIntervalSince1970: epoch).formatted(date: .abbreviated, time: .shortened)
        }
        if name == "duration" || name.hasSuffix("Offset") { return runtime(value) }
        if name == "size", let bytes = Int64(value), bytes > 100_000 {
            return bytes.formatted(.byteCount(style: .file))
        }
        if name == "bitrate", let kbps = Int(value) {
            return kbps >= 1000 ? String(format: "%.1f Mbps", Double(kbps) / 1000) : "\(kbps) kbps"
        }
        return nil
    }

    static func runtime(_ value: String?) -> String? {
        guard let value, let ms = Int(value), ms >= 1000 else { return nil }
        return Duration.milliseconds(ms).formatted(.time(pattern: ms >= 3_600_000 ? .hourMinuteSecond : .minuteSecond))
    }

    static func rating(_ value: String?) -> String? {
        guard let value, let number = Double(value) else { return nil }
        return "★ \(number.formatted(.number.precision(.fractionLength(1))))"
    }

    static func count(_ value: String?, _ singular: String, _ plural: String) -> String? {
        guard let value, let n = Int(value), n > 0 else { return nil }
        return "\(n) \(n == 1 ? singular : plural)"
    }
}
