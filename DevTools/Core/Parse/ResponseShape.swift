import Foundation

/// The attribute and element names present on a container's items — the
/// vocabulary for `includeFields` / `excludeFields` / `includeElements` /
/// `excludeElements`, which Plex documents but nothing surfaces.
struct ResponseShape: Sendable, Hashable {
    /// The query parameters Plex reads to shape a response.
    static let parameters = ["includeFields", "excludeFields", "includeElements", "excludeElements"]

    let fields: [String]
    let elements: [String]

    var isEmpty: Bool { fields.isEmpty && elements.isEmpty }

    /// Names are taken from the container's items (`Metadata`, `Directory`,
    /// `Hub`…), not the container itself, since that's what the params shape.
    init(root: Node) {
        var fields = Set<String>()
        var elements = Set<String>()
        for item in root.children {
            for attribute in item.attributes { fields.insert(attribute.name) }
            for child in item.children { elements.insert(child.name) }
        }
        self.fields = fields.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        self.elements = elements.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
