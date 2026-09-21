import Foundation

struct Attribute: Sendable, Hashable, Identifiable {
    let id: Int
    let name: String
    let value: String
}

struct Node: Sendable, Hashable, Identifiable {
    let id: Int
    let name: String
    let attributes: [Attribute]
    let children: [Node]

    subscript(_ attribute: String) -> String? {
        attributes.first { $0.name == attribute }?.value
    }

    var headline: String {
        for key in ["title", "tag", "name", "label", "key"] {
            if let value = self[key], !value.isEmpty { return value }
        }
        return name
    }

    var count: Int {
        1 + children.reduce(0) { $0 + $1.count }
    }
}

struct IDCounter {
    private var next = 0

    mutating func take() -> Int {
        defer { next += 1 }
        return next
    }
}
