import Foundation
import Testing
@testable import DevTools

struct FoldingTests {
    private func slice(_ text: String, _ start: Int, _ end: Int) -> String {
        let utf16 = Array(text.utf16)
        return String(decoding: utf16[start..<end], as: UTF16.self)
    }

    @Test func jsonRegionsCountDirectChildrenAndSkipEmptyContainers() {
        let text = JSONFormatter.pretty(Data(#"{"MediaContainer":{"size":2,"Metadata":[{"a":1},{"b":[1,2,3]}],"empty":{},"list":[]}}"#.utf8))
        let regions = Folding.jsonRegions(text: text, tokens: Highlighter.json(text))

        // root, MediaContainer, Metadata, {a}, {b}, b's array — no regions for {} or [].
        #expect(regions.count == 6)
        let root = regions[0]
        #expect(root.depth == 0 && root.count == 1)
        let container = regions[1]
        #expect(container.depth == 1 && container.count == 4)
        let metadata = regions[2]
        #expect(metadata.count == 2)
        #expect(slice(text, metadata.anchor.location, metadata.anchor.location + 1) == "[")
        #expect(slice(text, metadata.hiddenEnd, metadata.hiddenEnd + 1) == "]")
        #expect(regions.contains { $0.count == 3 && $0.depth == 4 })
    }

    @Test func xmlRegionsFoldElementsWithContentOnly() {
        let text = """
        <MediaContainer size="2">
          <Video title="Heat"><Media id="1"><Part id="2"/></Media><Genre tag="Crime"/></Video>
          <Directory key="collections"/>
        </MediaContainer>
        """
        let regions = Folding.xmlRegions(text: text, tokens: Highlighter.xml(text))
        let names = regions.map { slice(text, $0.anchor.location, $0.anchor.location + $0.anchor.length) }
        #expect(names == ["MediaContainer", "Video", "Media"])
        #expect(regions[0].count == 2)
        #expect(regions[1].count == 2)
        #expect(regions[2].count == 1)
        #expect(slice(text, regions[1].hiddenEnd, regions[1].hiddenEnd + 2) == "</")
    }

    @Test func effectiveDropsRegionsNestedInsideCollapsedOnes() {
        let text = JSONFormatter.pretty(Data(#"{"a":{"b":{"c":1}},"d":[1]}"#.utf8))
        let regions = Folding.jsonRegions(text: text, tokens: Highlighter.json(text))
        let a = regions.first { $0.depth == 1 && $0.count == 1 && slice(text, $0.anchor.location, $0.anchor.location + 1) == "{" }!
        let b = regions.first { $0.depth == 2 }!
        let d = regions.first { slice(text, $0.anchor.location, $0.anchor.location + 1) == "[" }!

        let effective = Folding.effective(regions, collapsed: [a.id, b.id, d.id])
        #expect(effective.map(\.id) == [a.id, d.id])
    }
}
