import Foundation
import Testing
@testable import DevTools

struct NodeParserTests {
    private let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <MediaContainer size="2" allowSync="0" title1="Movies">
      <Video ratingKey="10" key="/library/metadata/10" type="movie" title="Heat" year="1995" addedAt="1700000000">
        <Media id="1" duration="10200000" bitrate="12000">
          <Part id="2" file="/media/heat.mkv" size="15000000000"/>
        </Media>
        <Genre tag="Crime"/>
        <Genre tag="Thriller"/>
      </Video>
      <Directory key="collections" title="Collections"/>
    </MediaContainer>
    """

    private let json = """
    {"MediaContainer":{"size":2,"allowSync":false,"title1":"Movies","Metadata":[
      {"ratingKey":"10","key":"/library/metadata/10","type":"movie","title":"Heat","year":1995,"addedAt":1700000000,
       "Media":[{"id":1,"duration":10200000,"bitrate":12000,"Part":[{"id":2,"file":"/media/heat.mkv","size":15000000000}]}],
       "Genre":[{"tag":"Crime"},{"tag":"Thriller"}]},
      {"key":"collections","title":"Collections"}
    ]}}
    """

    /// Strip IDs and element names (XML uses Video/Directory, JSON uses
    /// Metadata) so the structural comparison is about attributes and shape.
    private func shape(_ node: Node) -> String {
        let attrs = node.attributes.map { "\($0.name)=\($0.value)" }.joined(separator: " ")
        let kids = node.children.map(shape).joined(separator: ",")
        return "(\(attrs))[\(kids)]"
    }

    @Test func xmlAndJSONProduceTheSameShape() throws {
        let fromXML = try #require(XMLNodeParser.parse(Data(xml.utf8)))
        let fromJSON = try #require(JSONNodeParser.parse(Data(json.utf8)))

        #expect(fromXML.name == "MediaContainer")
        #expect(fromJSON.name == "MediaContainer")
        #expect(shape(fromXML) == shape(fromJSON))
    }

    @Test func xmlKeepsElementNamesAndOrder() throws {
        let root = try #require(XMLNodeParser.parse(Data(xml.utf8)))
        #expect(root.children.map(\.name) == ["Video", "Directory"])
        #expect(root.children[0].children.map(\.name) == ["Media", "Genre", "Genre"])
        #expect(root.children[0]["title"] == "Heat")
        #expect(root["size"] == "2")
    }

    @Test func jsonBooleansMatchXMLIntegers() throws {
        let root = try #require(JSONNodeParser.parse(Data(json.utf8)))
        #expect(root["allowSync"] == "0")
        #expect(root.children[0].children[0]["duration"] == "10200000")
    }

    @Test func idsAreUniqueAcrossNodesAndAttributes() throws {
        let root = try #require(XMLNodeParser.parse(Data(xml.utf8)))
        var seen = Set<Int>()
        func walk(_ node: Node) {
            #expect(seen.insert(node.id).inserted)
            for attribute in node.attributes { #expect(seen.insert(attribute.id).inserted) }
            node.children.forEach(walk)
        }
        walk(root)
        #expect(root.count == 7)
    }

    @Test func headlinePrefersTitleThenTagThenName() {
        let a = Attribute(id: 0, name: "tag", value: "Crime")
        #expect(Node(id: 1, name: "Genre", attributes: [a], children: []).headline == "Crime")
        #expect(Node(id: 2, name: "Media", attributes: [], children: []).headline == "Media")
    }
}

struct LinkDetectorTests {
    @Test func relativeKeyResolvesAgainstRequestPathWithTrailingSlashRule() {
        #expect(LinkDetector.resolve("home", relativeTo: "/library/sections") == .server(path: "/library/sections/home"))
        #expect(LinkDetector.resolve("home", relativeTo: "/library/sections/") == .server(path: "/library/sections/home"))
        #expect(LinkDetector.resolve("children", relativeTo: "/library/metadata/10?includeChildren=1") == .server(path: "/library/metadata/10/children"))
    }

    @Test func absolutePathIsUsedAsIs() {
        #expect(LinkDetector.resolve("/library/metadata/10", relativeTo: "/library/sections/1/all") == .server(path: "/library/metadata/10"))
    }

    @Test func urlsWithSchemeAreExternal() {
        #expect(LinkDetector.resolve("https://metadata-static.plex.tv/x.jpg", relativeTo: "/") == .external(URL(string: "https://metadata-static.plex.tv/x.jpg")!))
        #expect(LinkDetector.resolve("view://home", relativeTo: "/") == .external(URL(string: "view://home")!))
        #expect(LinkDetector.resolve("", relativeTo: "/") == nil)
    }

    @Test func onlyWhitelistedAttributesAreNavigable() {
        #expect(LinkDetector.isNavigable(Attribute(id: 0, name: "key", value: "/x")))
        #expect(LinkDetector.isNavigable(Attribute(id: 0, name: "thumb", value: "/library/metadata/1/thumb/2")))
        #expect(!LinkDetector.isNavigable(Attribute(id: 0, name: "file", value: "/media/heat.mkv")))
        #expect(!LinkDetector.isNavigable(Attribute(id: 0, name: "ratingKey", value: "10")))
        #expect(!LinkDetector.isNavigable(Attribute(id: 0, name: "key", value: "")))
    }
}
