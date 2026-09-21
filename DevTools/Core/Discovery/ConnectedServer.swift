import Foundation

/// A server plus the specific connection we're talking to it over.
struct ConnectedServer: Sendable, Hashable, Identifiable {
    var id: String { machineID }

    let machineID: String
    let name: String
    let baseURL: URL
    let accessToken: String
    let connection: Connection
    let owned: Bool
}
