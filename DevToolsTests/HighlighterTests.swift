import Foundation
import Testing
@testable import DevTools

struct HighlighterTests {
    private func slice(_ text: String, _ token: Token) -> String {
        let utf16 = Array(text.utf16)
        return String(decoding: utf16[token.location..<(token.location + token.length)], as: UTF16.self)
    }

    @Test func jsonDistinguishesKeysFromStringValues() {
        let text = #"{"title": "Movie: The \"Sequel\"", "n": -12.5e3, "ok": true, "x": null, "y": nullish}"#
        let tokens = Highlighter.json(text)

        let keys = tokens.filter { $0.kind == .key }.map { slice(text, $0) }
        let strings = tokens.filter { $0.kind == .string }.map { slice(text, $0) }
        let numbers = tokens.filter { $0.kind == .number }.map { slice(text, $0) }
        let literals = tokens.filter { $0.kind == .literal }.map { slice(text, $0) }
        let nulls = tokens.filter { $0.kind == .null }.map { slice(text, $0) }

        #expect(keys == [#""title""#, #""n""#, #""ok""#, #""x""#, #""y""#])
        #expect(strings == [#""Movie: The \"Sequel\"""#])
        #expect(numbers == ["-12.5e3"])
        #expect(literals == ["true", "nullish"])
        #expect(nulls == ["null"])
    }

    @Test func jsonStringContainingColonIsNotAKey() {
        let text = #"["a:b", "c"]"#
        let tokens = Highlighter.json(text)
        #expect(tokens.filter { $0.kind == .key }.isEmpty)
        #expect(tokens.filter { $0.kind == .string }.count == 2)
    }

    @Test func xmlTagsAttributesAndComments() {
        let text = #"<?xml version="1.0"?><!-- note --><MediaContainer size="2" title='It&apos;s'><Video key="/library/metadata/1"/></MediaContainer>"#
        let tokens = Highlighter.xml(text)

        #expect(tokens.filter { $0.kind == .processingInstruction }.map { slice(text, $0) } == [#"<?xml version="1.0"?>"#])
        #expect(tokens.filter { $0.kind == .comment }.map { slice(text, $0) } == ["<!-- note -->"])
        #expect(tokens.filter { $0.kind == .tagName }.map { slice(text, $0) } == ["MediaContainer", "Video", "MediaContainer"])
        #expect(tokens.filter { $0.kind == .attributeName }.map { slice(text, $0) } == ["size", "title", "key"])
        #expect(tokens.filter { $0.kind == .attributeValue }.map { slice(text, $0) } == [#""2""#, "'It&apos;s'", #""/library/metadata/1""#])
    }

    @Test func xmlAttributeValueWithGreaterThanInsideQuotes() {
        let text = #"<a title="1 > 0" b="x"/>"#
        let tokens = Highlighter.xml(text)
        #expect(tokens.filter { $0.kind == .attributeValue }.map { slice(text, $0) } == [#""1 > 0""#, #""x""#])
        #expect(tokens.filter { $0.kind == .attributeName }.map { slice(text, $0) } == ["title", "b"])
    }

    @Test func tokensStayInsideTextOnTruncatedInput() {
        for text in [#"{"a": "unterminated"#, "<Video key=\"/x", "<!-- open", #"[1, 2,"#] {
            let length = text.utf16.count
            for token in Highlighter.json(text) + Highlighter.xml(text) {
                #expect(token.location + token.length <= length)
            }
        }
    }
}
