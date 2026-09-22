import Foundation
import os

/// Frames are parsed here on the receive task, off the main actor, so the
/// store only inserts.
enum StreamEvent: Sendable {
    case opened
    case message(NotificationEvent)
}

enum NotificationTransportError: Error, LocalizedError {
    case badURL
    case status(Int)
    case closed

    var errorDescription: String? {
        switch self {
        case .badURL: "Couldn't build the notification URL."
        case .status(let code): "Server answered HTTP \(code)."
        case .closed: "The connection closed."
        }
    }
}

enum NotificationTransport {
    static let log = Logger(subsystem: "mldgg.devtools", category: "activity")

    /// PMS's own OpenAPI doc lists the singular `/:/websocket/…`, but the
    /// server only routes the plural (see python-plexapi's AlertListener).
    static let path = "/:/websockets/notifications"

    private static func request(server: ConnectedServer, identity: ClientIdentity) throws -> URLRequest {
        var components = URLComponents(url: server.baseURL, resolvingAgainstBaseURL: false)!
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = path
        components.queryItems = [URLQueryItem(name: "X-Plex-Token", value: server.accessToken)]
        guard let url = components.url else { throw NotificationTransportError.badURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        for (name, value) in identity.headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.setValue(server.accessToken, forHTTPHeaderField: "X-Plex-Token")
        return request
    }

    /// URLSession reports a rejected WebSocket upgrade as an opaque
    /// `badServerResponse`; the actual status is on `task.response`.
    private static func handshakeError(_ error: Error, task: URLSessionWebSocketTask) -> Error {
        if let http = task.response as? HTTPURLResponse, http.statusCode != 101 {
            return NotificationTransportError.status(http.statusCode)
        }
        return error
    }

    static func stream(server: ConnectedServer, identity: ClientIdentity) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let request: URLRequest
            do {
                request = try self.request(server: server, identity: identity)
            } catch {
                continuation.finish(throwing: error)
                return
            }
            log.info("websocket connecting to \(request.url?.host() ?? "?", privacy: .public)")

            let session = URLSession(configuration: .ephemeral)
            let task = session.webSocketTask(with: request)
            task.resume()

            task.sendPing { error in
                if let error {
                    let resolved = handshakeError(error, task: task)
                    log.error("websocket handshake failed: \(resolved.localizedDescription, privacy: .public)")
                    continuation.finish(throwing: resolved)
                } else {
                    log.info("websocket open")
                    continuation.yield(.opened)
                }
            }

            let receiver = Task {
                do {
                    while !Task.isCancelled {
                        let message = try await task.receive()
                        switch message {
                        case .string(let text):
                            log.debug("websocket frame \(text.count) chars")
                            continuation.yield(.message(NotificationEvent.make(raw: text)))
                        case .data(let data):
                            log.debug("websocket binary frame \(data.count) bytes")
                            continuation.yield(.message(NotificationEvent.make(raw: String(decoding: data, as: UTF8.self))))
                        @unknown default:
                            continue
                        }
                    }
                } catch {
                    let resolved = handshakeError(error, task: task)
                    if !Task.isCancelled {
                        log.error("websocket receive failed: \(resolved.localizedDescription, privacy: .public) (close code \(task.closeCode.rawValue))")
                    }
                    continuation.finish(throwing: Task.isCancelled ? CancellationError() : resolved)
                }
            }

            // Keep NAT/proxies from dropping an idle socket.
            let pinger = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    guard !Task.isCancelled else { return }
                    task.sendPing { error in
                        if let error { log.error("websocket ping failed: \(error.localizedDescription, privacy: .public)") }
                    }
                }
            }

            continuation.onTermination = { reason in
                log.info("websocket stream terminated: \(String(describing: reason), privacy: .public)")
                receiver.cancel()
                pinger.cancel()
                task.cancel(with: .goingAway, reason: nil)
                session.invalidateAndCancel()
            }
        }
    }
}
