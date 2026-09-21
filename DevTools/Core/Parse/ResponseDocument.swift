import Foundation

struct ResponseDocument: Sendable {
    enum Format: Sendable {
        case json, xml, image, text

        var label: String {
            switch self {
            case .json: "JSON"
            case .xml: "XML"
            case .image: "Image"
            case .text: "Text"
            }
        }
    }

    /// Above this we skip colouring and the tree; tokenizing and attributing
    /// tens of MB is slow and the Pretty tab would get tens of thousands of
    /// cards. JSON is still pretty-printed — that's cheap, and a single
    /// multi-MB line is far slower to lay out than the same bytes as lines.
    static let highlightLimit = 4 * 1024 * 1024

    let text: String
    let tokens: [Token]
    let format: Format
    let notice: String?
    let tree: Node?
    let folds: [FoldRegion]

    init(text: String, tokens: [Token], format: Format, notice: String?, tree: Node?, folds: [FoldRegion] = []) {
        self.text = text
        self.tokens = tokens
        self.format = format
        self.notice = notice
        self.tree = tree
        self.folds = folds
    }

    static func make(from response: PlexResponse) async -> ResponseDocument {
        await Task.detached(priority: .userInitiated) {
            build(body: response.body, contentType: response.contentType)
        }.value
    }

    static func build(body: Data, contentType: String?) -> ResponseDocument {
        let format = detectFormat(body: body, contentType: contentType)

        if format == .image {
            return ResponseDocument(text: "", tokens: [], format: .image, notice: nil, tree: nil)
        }

        guard body.count <= highlightLimit else {
            return ResponseDocument(
                text: format == .json ? JSONFormatter.pretty(body) : String(decoding: body, as: UTF8.self),
                tokens: [],
                format: format,
                notice: "Highlighting and tree skipped: \(body.count.formatted(.byteCount(style: .file))) exceeds the limit.",
                tree: nil
            )
        }

        switch format {
        case .json:
            let text = JSONFormatter.pretty(body)
            let tokens = Highlighter.json(text)
            return ResponseDocument(text: text, tokens: tokens, format: .json, notice: nil, tree: JSONNodeParser.parse(body), folds: Folding.jsonRegions(text: text, tokens: tokens))
        case .xml:
            let text = String(decoding: body, as: UTF8.self)
            let tokens = Highlighter.xml(text)
            return ResponseDocument(text: text, tokens: tokens, format: .xml, notice: nil, tree: XMLNodeParser.parse(body), folds: Folding.xmlRegions(text: text, tokens: tokens))
        case .text, .image:
            return ResponseDocument(text: String(decoding: body, as: UTF8.self), tokens: [], format: .text, notice: nil, tree: nil)
        }
    }

    private static func detectFormat(body: Data, contentType: String?) -> Format {
        if let contentType {
            let lower = contentType.lowercased()
            if lower.contains("json") { return .json }
            if lower.contains("xml") { return .xml }
            if lower.hasPrefix("image/") { return .image }
        }
        guard let first = body.first(where: { $0 != 0x20 && $0 != 0x09 && $0 != 0x0A && $0 != 0x0D }) else { return .text }
        switch first {
        case 0x7B, 0x5B: return .json
        case 0x3C: return .xml
        default: return .text
        }
    }
}
