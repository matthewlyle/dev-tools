import Foundation

/// Attributes are sorted because `XMLParser` hands them over unordered; `JSONNodeParser` sorts to match.
final class XMLNodeParser: NSObject, XMLParserDelegate {
    private struct Frame {
        let id: Int
        let name: String
        let attributes: [Attribute]
        var children: [Node] = []
    }

    private var ids = IDCounter()
    private var stack: [Frame] = []
    private var root: Node?

    static func parse(_ data: Data) -> Node? {
        let delegate = XMLNodeParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        guard parser.parse() || delegate.root != nil else { return nil }
        return delegate.root
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes attributeDict: [String: String]
    ) {
        let id = ids.take()
        let attributes = attributeDict
            .sorted { $0.key < $1.key }
            .map { Attribute(id: ids.take(), name: $0.key, value: $0.value) }
        stack.append(Frame(id: id, name: elementName, attributes: attributes))
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        guard let frame = stack.popLast() else { return }
        let node = Node(id: frame.id, name: frame.name, attributes: frame.attributes, children: frame.children)
        if stack.isEmpty {
            root = node
        } else {
            stack[stack.count - 1].children.append(node)
        }
    }
}
