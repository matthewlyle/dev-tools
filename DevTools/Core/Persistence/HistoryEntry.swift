import Foundation

struct HistoryEntry: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var request: PlexRequest
    let serverID: String
    let serverName: String
    let status: Int?
    let durationMilliseconds: Int?
    let error: String?
    let date: Date

    var succeeded: Bool {
        guard let status else { return false }
        return (200..<300).contains(status)
    }

    var sortStatus: Int { status ?? Int.max }
    var sortDuration: Int { durationMilliseconds ?? Int.max }
}
