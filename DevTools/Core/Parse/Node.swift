import Foundation

/// One attribute on a node. IDs are unique across the whole document so
/// attributes and nodes can share an outline.
struct Attribute: Sendable, Hashable, Identifiable {
    let id: Int
    let name: String
    let value: String
}

/// Format-neutral view of a Plex response. XML elements and JSON objects
/// both become nodes; XML attributes and JSON scalars both become
/// attributes; nested elements and arrays-of-objects both become children.
struct Node: Sendable, Hashable, Identifiable {
    let id: Int
    let name: String
    let attributes: [Attribute]
    let children: [Node]

    subscript(_ attribute: String) -> String? {
        attributes.first { $0.name == attribute }?.value
    }

    /// Best human label: title-like attribute, else the node name.
    var headline: String {
        for key in ["title", "tag", "name", "label", "key"] {
            if let value = self[key], !value.isEmpty { return value }
        }
        return name
    }

    /// Total node count including self; used to decide how much to render.
    var count: Int {
        1 + children.reduce(0) { $0 + $1.count }
    }
}

/// Hands out document-unique IDs during a parse.
struct IDCounter {
    private var next = 0

    mutating func take() -> Int {
        defer { next += 1 }
        return next
    }
}
