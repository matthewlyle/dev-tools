import Foundation
import Testing
@testable import DevTools

struct SpecCatalogTests {
    private static let catalog: SpecCatalog = {
        let url = Bundle(for: Marker.self).url(forResource: "plex-openapi", withExtension: "json")
            ?? Bundle.main.url(forResource: "plex-openapi", withExtension: "json")!
        let spec = try! JSONDecoder().decode(OpenAPISpec.self, from: Data(contentsOf: url))
        return SpecCatalog(spec: spec)
    }()

    private final class Marker {}

    private var catalog: SpecCatalog { Self.catalog }

    @Test func loadsBundledSpec() {
        #expect(catalog.operations.count > 100)
        #expect(catalog.groups.contains { $0.name == "Library" })
        #expect(catalog.documentedHeaders.contains { $0.name == "X-Plex-Container-Size" })
    }

    @Test func docsLinksAreDerivedFromTagAndOperationID() throws {
        let root = try #require(catalog.match(path: "/"))
        #expect(root.docsURL?.absoluteString == "https://developer.plex.tv/pms/#tag/General/operation/getSlash")

        let spaced = SpecOperation(template: "/x", tag: "Live TV", operationID: "getX", summary: "", description: nil, parameters: [], supportsMediaQuery: false, access: .anyUser)
        #expect(spaced.docsURL?.absoluteString == "https://developer.plex.tv/pms/#tag/Live%20TV/operation/getX")

        #expect(catalog.operations.allSatisfy { $0.docsURL != nil })
    }

    @Test func accessComesFromSecurityScopes() throws {
        #expect(try #require(catalog.match(path: "/butler")).access == .admin)
        #expect(try #require(catalog.match(path: "/status/sessions")).access == .admin)
        #expect(try #require(catalog.match(path: "/identity")).access == .open)
        #expect(try #require(catalog.match(path: "/library/sections/all")).access == .anyUser)
        #expect(catalog.operations.filter { $0.access == .admin }.count == 19)
    }

    @Test func groupsFilterByTemplateSummaryOrTag() {
        #expect(catalog.groups(matching: "   ").count == catalog.groups.count)

        let sections = catalog.groups(matching: "library/sections")
        #expect(!sections.isEmpty)
        #expect(sections.allSatisfy { group in
            group.operations.allSatisfy { $0.template.localizedCaseInsensitiveContains("library/sections") }
        })

        let library = catalog.groups(matching: "library").first { $0.name == "Library" }
        #expect(library?.operations.count == catalog.groups.first { $0.name == "Library" }?.operations.count)

        #expect(catalog.groups(matching: "definitely-not-an-endpoint").isEmpty)
    }

    @Test func literalRouteBeatsPlaceholderRoute() throws {
        let all = try #require(catalog.match(path: "/library/sections/all"))
        #expect(all.template == "/library/sections/all")

        let one = try #require(catalog.match(path: "/library/sections/3"))
        #expect(one.template == "/library/sections/{sectionId}")
    }

    @Test func matchesIgnoreQueryAndTrailingSlash() throws {
        let op = try #require(catalog.match(path: "/library/sections/3/all?type=1&sort=titleSort"))
        #expect(op.template == "/library/sections/{sectionId}/all")
        #expect(op.supportsMediaQuery)
        #expect(catalog.match(path: "/identity/")?.template == "/identity")
    }

    @Test func placeholdersInsideSegmentsMatch() throws {
        let epg = try #require(catalog.match(path: "/tv.plex.providers.epg.xmltv:5/grid"))
        #expect(epg.template == "/tv.plex.providers.epg.{identifier}:{deviceId}/grid")

        let stream = try #require(catalog.match(path: "/library/streams/42.srt"))
        #expect(stream.template == "/library/streams/{streamId}.{ext}")
    }

    @Test func unknownPathsDoNotMatch() {
        #expect(catalog.match(path: "/definitely/not/documented") == nil)
        #expect(catalog.match(path: "/library/sections/3/all/extra") == nil)
    }

    @Test func placeholderFillingAndOrder() throws {
        let op = try #require(catalog.match(path: "/library/sections/3/all"))
        #expect(op.placeholders == ["sectionId"])
        #expect(op.path(filling: ["sectionId": "7"]) == "/library/sections/7/all")
        #expect(op.path(filling: ["sectionId": ""]) == "/library/sections/{sectionId}/all")
        #expect(op.pathParameters.map(\.name) == ["sectionId"])
    }
}

struct PaginationTests {
    private func response(headers: [String: String]) -> PlexResponse {
        PlexResponse(url: URL(string: "https://x/y")!, status: 200, headers: headers, body: Data(), duration: .zero, receivedAt: .now)
    }

    private func root(_ attributes: [String: String], children: Int = 0) -> Node {
        var id = 1
        let attrs = attributes.sorted { $0.key < $1.key }.map { pair -> Attribute in
            defer { id += 1 }
            return Attribute(id: id, name: pair.key, value: pair.value)
        }
        let kids = (0..<children).map { Node(id: 100 + $0, name: "Metadata", attributes: [], children: []) }
        return Node(id: 0, name: "MediaContainer", attributes: attrs, children: kids)
    }

    @Test func headersTakePrecedenceOverBody() throws {
        let info = try #require(PaginationInfo(response: response(headers: ["X-Plex-Container-Start": "40", "x-plex-container-total-size": "1204"]), root: root(["offset": "0", "size": "20", "totalSize": "5"])))
        #expect(info.start == 40)
        #expect(info.total == 1204)
        #expect(info.size == 20)
        #expect(info.label == "41–60 of 1,204")
        #expect(info.hasPrevious && info.hasNext)
    }

    @Test func bodyAttributesSufficeWithoutHeaders() throws {
        let info = try #require(PaginationInfo(response: response(headers: [:]), root: root(["offset": "100", "size": "50", "totalSize": "120"])))
        #expect(info.end == 120)
        #expect(!info.hasNext)
        #expect(info.pageSize == 50)
    }

    @Test func unpaginatedResponseHasNoInfo() {
        #expect(PaginationInfo(response: response(headers: [:]), root: root(["size": "3"], children: 3)) == nil)
    }

    @Test func countOnlyResponseUsesDefaultPageSize() throws {
        let info = try #require(PaginationInfo(response: response(headers: ["X-Plex-Container-Total-Size": "99"]), root: root(["size": "0", "offset": "0"])))
        #expect(info.label == "0 of 99")
        #expect(info.pageSize == PaginationInfo.defaultPageSize)
        #expect(info.hasNext)
    }
}
