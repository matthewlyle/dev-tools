import Foundation
import Testing
@testable import DevTools

struct MetadataTypeTests {
    private final class Marker {}

    private static func specTable() throws -> [String: Int] {
        let url = Bundle(for: Marker.self).url(forResource: "plex-openapi", withExtension: "json")
            ?? Bundle.main.url(forResource: "plex-openapi", withExtension: "json")!
        let root = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let info = try #require(root["info"] as? [String: Any])
        let description = try #require(info["description"] as? String)
        let section = try #require(description.range(of: "### List of Metadata Types"))
        var table: [String: Int] = [:]
        var started = false
        for line in description[section.upperBound...].split(separator: "\n", omittingEmptySubsequences: false).dropFirst() {
            guard line.hasPrefix("|") else {
                if started { break } else { continue }
            }
            started = true
            let cells = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count == 2, let number = Int(cells[1]) else { continue }
            table[cells[0].trimmingCharacters(in: CharacterSet(charactersIn: "`"))] = number
        }
        return table
    }

    @Test func tableMatchesTheBundledSpec() throws {
        let table = try Self.specTable()
        #expect(!table.isEmpty)
        #expect(MetadataType.numbers == table)
    }

    @Test func typeNumbersDecodeToNames() {
        #expect(MediaValue.display(name: "type", value: "4") == "episode (4)")
        #expect(MediaValue.display(name: "metadataType", value: "18") == "collection (18)")
    }

    @Test func onlyKnownNumbersUnderTypeNamesDecode() {
        #expect(MediaValue.display(name: "type", value: "movie") == nil)
        #expect(MediaValue.display(name: "type", value: "6") == nil)
        #expect(MediaValue.display(name: "streamType", value: "1") == nil)
    }

    @Test func queryTypeParameterOffersTheTypes() {
        let parameter = SpecParameter(name: "type", location: .query, description: nil, required: false, type: "integer", enumValues: [], defaultValue: nil, example: nil)
        let options = parameter.valueOptions
        #expect(options.first?.value == "1")
        #expect(options.first?.label == "movie (1)")
        #expect(options.count == MetadataType.numbers.count)
    }
}
