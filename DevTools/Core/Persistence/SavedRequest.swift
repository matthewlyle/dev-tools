import Foundation

struct SavedRequest: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var request: PlexRequest
    let serverID: String
    let createdAt: Date
}
