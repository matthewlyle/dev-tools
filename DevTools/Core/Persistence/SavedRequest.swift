import Foundation

/// A request kept on purpose, scoped to the server it was built against.
struct SavedRequest: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var notes: String
    var request: PlexRequest
    let serverID: String
    let createdAt: Date
}
