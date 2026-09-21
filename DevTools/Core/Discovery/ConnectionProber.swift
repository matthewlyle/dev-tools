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
}

struct ConnectionProber: Sendable {
    private let http: PlexHTTP
    private let timeout: TimeInterval

    init(http: PlexHTTP, timeout: TimeInterval = 6) {
        self.http = http
        self.timeout = timeout
    }

    func probeAll(_ resource: PlexResource) async -> [ProbeResult] {
        guard let token = resource.accessToken else {
            return resource.connections.map {
                ProbeResult(connection: $0, outcome: .failed("No access token for this resource"))
            }
        }

        let results = await withTaskGroup(of: ProbeResult.self) { group in
            for connection in resource.connections {
                group.addTask {
                    await probe(connection, expecting: resource.clientIdentifier, token: token)
                }
            }
            var collected: [ProbeResult] = []
            collected.reserveCapacity(resource.connections.count)
            for await result in group { collected.append(result) }
            return collected
        }

        return results.sorted { lhs, rhs in
            if lhs.connection.rank != rhs.connection.rank { return lhs.connection.rank < rhs.connection.rank }
            return lhs.connection.uri < rhs.connection.uri
        }
    }

    private func probe(_ connection: Connection, expecting machineID: String, token: String) async -> ProbeResult {
        guard let base = connection.url else {
            return ProbeResult(connection: connection, outcome: .failed("Malformed URI"))
        }

        let request = PlexRequest(path: "/identity")

        do {
            let response = try await http.send(request, baseURL: base, token: token, timeout: timeout)
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
