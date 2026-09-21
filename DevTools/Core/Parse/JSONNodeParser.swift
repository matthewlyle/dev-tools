import Foundation

/// Builds a `Node` tree from Plex JSON. A top-level object with a single
/// object value (`{"MediaContainer": {…}}`) becomes the root node; members
/// that are arrays of objects become repeated child nodes named by the member
/// key, in source order; scalar members become attributes, sorted by name to
/// match the XML parser (whose attribute order is not recoverable).
enum JSONNodeParser {
    static func parse(_ data: Data) -> Node? {
        guard let value = JSONValue.parse(data) else { return nil }
        var ids = IDCounter()

        switch value {
        case .object(let members):
            if members.count == 1, case .object(let inner) = members[0].value {
                return node(named: members[0].key, from: inner, ids: &ids)
            }
            return node(named: "root", from: members, ids: &ids)
        case .array(let items):
            let id = ids.take()
            let children = items.compactMap { item -> Node? in
                guard case .object(let members) = item else { return nil }
                return node(named: "item", from: members, ids: &ids)
            }
            return Node(id: id, name: "root", attributes: [], children: children)
        default:
            return nil
        }
    }

    private static func node(named name: String, from members: [(key: String, value: JSONValue)], ids: inout IDCounter) -> Node {
        let id = ids.take()
        var scalars: [(String, String)] = []
        var children: [Node] = []

        for (key, value) in members {
            switch value {
            case .object(let inner):
                children.append(node(named: key, from: inner, ids: &ids))
            case .array(let items):
                let objects = items.compactMap { item -> [(key: String, value: JSONValue)]? in
                    guard case .object(let members) = item else { return nil }
                    return members
                }
                if objects.count == items.count {
                    for object in objects {
                        children.append(node(named: key, from: object, ids: &ids))
                    }
                } else {
                    scalars.append((key, items.map(scalarString).joined(separator: ",")))
                }
            default:
                scalars.append((key, scalarString(value)))
            }
        }

        let attributes = scalars
            .sorted { $0.0 < $1.0 }
            .map { Attribute(id: ids.take(), name: $0.0, value: $0.1) }
        return Node(id: id, name: name, attributes: attributes, children: children)
    }

    private static func scalarString(_ value: JSONValue) -> String {
        switch value {
        case .string(let s): s
        case .number(let n): n
        case .bool(let b): b ? "1" : "0"
        case .null: ""
        case .object, .array: ""
        }
    }
}
