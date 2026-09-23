import Foundation

/// A request kept on purpose, scoped to the server it was built against.
/// Files from before notes were dropped still decode: the `notes` key is
/// ignored.
struct SavedRequest: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var request: PlexRequest
    let serverID: String
    let createdAt: Date
}
