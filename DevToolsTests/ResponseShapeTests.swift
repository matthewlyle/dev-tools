import Foundation
import Testing
@testable import DevTools

struct ResponseShapeTests {
    @Test func collectsItemFieldsAndElementsNotContainerOnes() {
        let json = """
        {"MediaContainer":{"size":2,"identifier":"x","Metadata":[
          {"title":"A","year":2001,"Genre":[{"tag":"Drama"}],"Media":[{"id":1}]},
          {"title":"B","rating":7.5,"Director":[{"tag":"X"}]}
        ]}}
        """
        let root = JSONNodeParser.parse(Data(json.utf8))!
        let shape = ResponseShape(root: root)
        #expect(shape.fields == ["rating", "title", "year"])
        #expect(shape.elements == ["Director", "Genre", "Media"])
        #expect(!shape.fields.contains("identifier"))
    }

    @Test func emptyContainerHasNoShape() {
        let root = JSONNodeParser.parse(Data("{\"MediaContainer\":{\"size\":0}}".utf8))!
        #expect(ResponseShape(root: root).isEmpty)
    }
}
