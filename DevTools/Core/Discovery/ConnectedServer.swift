import Foundation

struct ConnectedServer: Sendable, Hashable, Identifiable {
    var id: String { machineID }

    let machineID: String
    let name: String
    let baseURL: URL
    let accessToken: String
    let connection: Connection
    let owned: Bool
}
