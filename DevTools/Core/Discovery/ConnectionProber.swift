import Foundation

struct ProbeResult: Sendable, Hashable, Identifiable {
    var id: String { connection.uri }

    let connection: Connection
    let outcome: Outcome

    enum Outcome: Sendable, Hashable {
        case ok(latency: Duration)
        case failed(String)

        var isOK: Bool {
            if case .ok = self { return true }
            return false
        }
    }

    static func ranked(_ lhs: ProbeResult, _ rhs: ProbeResult) -> Bool {
        if lhs.connection.rank != rhs.connection.rank { return lhs.connection.rank < rhs.connection.rank }
        return lhs.connection.uri < rhs.connection.uri
    }
}

struct ConnectionProber: Sendable {
    private let http: PlexHTTP
    private let timeout: TimeInterval

    init(http: PlexHTTP, timeout: TimeInterval = 6) {
        self.http = http
        self.timeout = timeout
    }

    /// Probes go out without the token: it only goes to a connection that answered with this server's ID.
    /// Plain HTTP is never probed, since only TLS proves who answered. Each result is reported as it
    /// lands: a connection that never answers holds its slot until the timeout, and shouldn't hold the rest.
    func probeAll(_ resource: PlexResource, report: @escaping @MainActor @Sendable (ProbeResult) -> Void) async {
        guard resource.accessToken != nil else {
            for connection in resource.connections {
                await report(ProbeResult(connection: connection, outcome: .failed("No access token for this resource")))
            }
            return
        }

        await withTaskGroup(of: ProbeResult.self) { group in
            for connection in resource.connections {
                guard connection.isHTTPS else {
                    group.addTask { ProbeResult(connection: connection, outcome: .failed("Not encrypted")) }
                    continue
                }
                group.addTask {
                    await probe(connection, expecting: resource.clientIdentifier)
                }
            }
            for await result in group { await report(result) }
        }
    }

    private func probe(_ connection: Connection, expecting machineID: String) async -> ProbeResult {
        guard let base = connection.url else {
            return ProbeResult(connection: connection, outcome: .failed("Malformed URI"))
        }

        let request = PlexRequest(path: "/identity")

        do {
            let response = try await http.send(request, baseURL: base, token: nil, timeout: timeout)
            guard response.status == 200 else {
                return ProbeResult(connection: connection, outcome: .failed("HTTP \(response.status)"))
            }
            guard let object = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any],
                  let container = object["MediaContainer"] as? [String: Any],
                  let reported = container["machineIdentifier"] as? String
            else {
                return ProbeResult(connection: connection, outcome: .failed("Unexpected /identity body"))
            }
            guard reported == machineID else {
                return ProbeResult(connection: connection, outcome: .failed("Machine ID mismatch"))
            }
            return ProbeResult(connection: connection, outcome: .ok(latency: response.duration))
        } catch let error as URLError {
            return ProbeResult(connection: connection, outcome: .failed(error.shortDescription))
        } catch {
            return ProbeResult(connection: connection, outcome: .failed(error.localizedDescription))
        }
    }
}

extension URLError {
    var shortDescription: String {
        switch code {
        case .timedOut: "Timed out"
        case .cannotConnectToHost: "Can't connect"
        case .cannotFindHost: "Host not found"
        case .networkConnectionLost: "Connection lost"
        case .notConnectedToInternet: "Offline"
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
            "TLS failed"
        default: localizedDescription
        }
    }
}
