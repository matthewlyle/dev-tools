import Foundation
import Testing
@testable import DevTools

struct JSONValueTests {
    private func value(_ json: String) throws -> JSONValue {
        try #require(JSONValue.parse(Data(json.utf8)))
    }

    @Test func prettyPrintKeepsOrderTypesAndEscapes() throws {
        let out = try value(#"{"z":1.50,"n":true,"s":"a\"b","a":[1,null],"o":{}}"#).prettyPrinted()
        #expect(out == """
        {
          "z": 1.50,
          "n": true,
          "s": "a\\"b",
          "a": [
            1,
            null
          ],
          "o": {}
        }
        """)
    }

    @Test func firstObjectFindsByScalarAnywhereInTree() throws {
        let root = try value(#"{"MediaContainer":{"Metadata":[{"ratingKey":"1","title":"A"},{"ratingKey":"2","title":"B","Media":[{"id":9}]}]}}"#)
        let hit = try #require(root.firstObject(scalar: "ratingKey", equals: "2"))
        #expect(hit.prettyPrinted() == """
        {
          "ratingKey": "2",
          "title": "B",
          "Media": [
            {
              "id": 9
            }
          ]
        }
        """)
        #expect(root.firstObject(scalar: "ratingKey", equals: "404") == nil)
    }

    @Test func firstObjectMatchesNumericScalarByItsSourceText() throws {
        let root = try value(#"{"Directory":[{"key":"12","title":"Genre"}]}"#)
        #expect(root.firstObject(scalar: "key", equals: "12")?.prettyPrinted().contains("\"title\": \"Genre\"") == true)
    }
}
