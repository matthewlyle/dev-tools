import Foundation
import Observation

/// Identifiers seen in responses, per server, so placeholders like
/// `{metadataId}` or `{deviceId}` can be filled from what you've already
/// looked at instead of retyped. The spec gives no machine-readable link
/// from a placeholder to its source, so this is the automatic alternative
/// to a hand-kept table.
@MainActor
@Observable
final class ValueMemory {
    struct Seen: Identifiable, Hashable, Sendable {
        var id: String { "\(element)|\(attribute)|\(value)" }
        let element: String
        let attribute: String
        let value: String
        let title: String
        let seenAt: Date
    }

    static let capacity = 400

    private(set) var seen: [String: [Seen]] = [:]
    private(set) var lastUsed: [String: [String: String]]

    private static let lastUsedFile = "placeholders.json"

    init() {
        lastUsed = AppSupportStore.load([String: [String: String]].self, name: Self.lastUsedFile) ?? [:]
    }

    /// Records every id-like attribute in `root`'s tree: `ratingKey`, `id`,
    /// `*ID`/`*Id`, and a numeric `key` (library sections). Newest first,
    /// de-duplicated, capped.
    func record(root: Node, serverID: String) {
        var fresh: [Seen] = []
        let now = Date.now
        func walk(_ node: Node, depth: Int) {
            guard depth < 6 else { return }
            for attribute in node.attributes where Self.isIdentifier(attribute.name, value: attribute.value) {
                fresh.append(Seen(element: node.name, attribute: attribute.name, value: attribute.value, title: node.headline, seenAt: now))
            }
            for child in node.children { walk(child, depth: depth + 1) }
        }
        for item in root.children { walk(item, depth: 0) }
        guard !fresh.isEmpty else { return }

        var merged = fresh
        var ids = Set(fresh.map(\.id))
        for old in seen[serverID] ?? [] where ids.insert(old.id).inserted {
            merged.append(old)
        }
        if merged.count > Self.capacity { merged.removeLast(merged.count - Self.capacity) }
        seen[serverID] = merged
    }

    private static func isIdentifier(_ name: String, value: String) -> Bool {
        guard !value.isEmpty, value.count <= 64 else { return false }
        if name == "ratingKey" || name == "id" { return true }
        if name.hasSuffix("ID") || name.hasSuffix("Id") { return true }
        return name == "key" && value.allSatisfy(\.isNumber)
    }

    /// Values that plausibly fill `placeholder`, newest first. Only matches:
    /// an unrelated identifier is noise, not a fallback.
    func candidates(for placeholder: String, serverID: String) -> [Seen] {
        let stem = Self.stem(of: placeholder)
        return (seen[serverID] ?? []).filter { Self.matches($0, stem: stem) }
    }

    /// `metadataId` → `metadata`, `ids` → `id`, `playQueueId` → `playqueue`.
    static func stem(of placeholder: String) -> String {
        var s = placeholder.lowercased()
        for suffix in ["ids", "id", "s"] where s.hasSuffix(suffix) && s.count > suffix.count {
            s.removeLast(suffix.count)
            break
        }
        return s
    }

    private static func matches(_ seen: Seen, stem: String) -> Bool {
        let element = seen.element.lowercased()
        switch stem {
        case "", "id", "item", "metadata":
            return seen.attribute == "ratingKey"
        case "section":
            return seen.attribute == "librarySectionID" || (element == "directory" && seen.attribute == "key")
        default:
            return element.hasPrefix(stem) || seen.attribute.lowercased() == stem + "id"
        }
    }

    func remember(placeholder: String, value: String, serverID: String) {
        lastUsed[serverID, default: [:]][placeholder] = value
        AppSupportStore.save(lastUsed, name: Self.lastUsedFile)
    }

    func lastUsed(placeholder: String, serverID: String) -> String? {
        lastUsed[serverID]?[placeholder]
    }
}
