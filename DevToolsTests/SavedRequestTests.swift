import Foundation
import Testing
@testable import DevTools

struct SavedRequestTests {
    @Test func filesFromBeforeNotesWereDroppedStillLoad() throws {
        let item = SavedRequest(id: UUID(), name: "Butler", request: PlexRequest(path: "/butler"), serverID: "abc", createdAt: .now)
        let encoded = try JSONEncoder().encode([item])
        var objects = try #require(try JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
        objects[0]["notes"] = "kept from an older version"
        let old = try JSONSerialization.data(withJSONObject: objects)

        let decoded = try JSONDecoder().decode([SavedRequest].self, from: old)
        #expect(decoded == [item])
    }
}
