import Foundation
import Testing
@testable import DevTools

struct JSONFormatterTests {
    private func pretty(_ s: String) -> String {
        JSONFormatter.pretty(Data(s.utf8))
    }

    @Test func preservesKeyOrderAndNumberFormatting() {
        let out = pretty(#"{"z":1.50,"a":[true,null],"m":{"k":"v"}}"#)
        #expect(out == """
        {
          "z": 1.50,
          "a": [
            true,
            null
          ],
          "m": {
            "k": "v"
          }
        }
        """)
    }

    @Test func emptyContainersStayInline() {
        #expect(pretty(#"{"a":{},"b":[ ]}"#) == """
        {
          "a": {},
          "b": []
        }
        """)
    }

    @Test func stringsAreCopiedVerbatim() {
        let out = pretty(#"{"s":"{ , : } [ ] \" \\"}"#)
        #expect(out == """
        {
          "s": "{ , : } [ ] \\" \\\\"
        }
        """)
    }

    @Test func alreadyPrettyInputIsNormalised() {
        let input = """
        {
            "a" :   1 ,
            "b":[1,2]
        }
        """
        #expect(pretty(input) == """
        {
          "a": 1,
          "b": [
            1,
            2
          ]
        }
        """)
    }

    @Test func responseDocumentDetectsFormatWithoutContentType() {
        let json = ResponseDocument.build(body: Data("  {\"a\":1}".utf8), contentType: nil)
        #expect(json.format == .json)
        #expect(json.text == "{\n  \"a\": 1\n}")
        #expect(json.tree?["a"] == "1")

        let xml = ResponseDocument.build(body: Data("<a b=\"c\"/>".utf8), contentType: nil)
        #expect(xml.format == .xml)
        #expect(xml.tree?.name == "a")

        let text = ResponseDocument.build(body: Data("hello".utf8), contentType: "text/plain")
        #expect(text.format == .text)
        #expect(text.tokens.isEmpty)
        #expect(text.tree == nil)

        let image = ResponseDocument.build(body: Data([0xFF, 0xD8]), contentType: "image/jpeg")
        #expect(image.format == .image)
    }
}
