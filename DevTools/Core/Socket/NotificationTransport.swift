import Foundation
import os

enum ActivityTransport: String, CaseIterable, Identifiable, Sendable {
    case webSocket = "WebSocket"
    case eventSource = "EventSource"

    var id: String { rawValue }

    /// PMS's own OpenAPI doc lists the singular `/:/websocket/…`, but the
    /// server only routes the plural (see python-plexapi's AlertListener).
    var path: String {
        switch self {
        case .webSocket: "/:/websockets/notifications"
        case .eventSource: "/:/eventsource/notifications"
        }
    }
}

/// A raw message from either transport.
struct RawNotification: Sendable {
    /// SSE `event:` name; WebSocket frames carry the type inside the JSON.
    let eventName: String?
    let data: String
}

enum StreamEvent: Sendable {
    /// The connection is established (handshake done), before any message.
    case opened
    case message(RawNotification)
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

/// Opens the server's notification feed and streams events until the
/// consumer stops iterating or the connection fails.
enum NotificationTransport {
    static let log = Logger(subsystem: "mldgg.devtools", category: "activity")

    static func stream(_ transport: ActivityTransport, server: ConnectedServer, identity: ClientIdentity) -> AsyncThrowingStream<StreamEvent, Error> {
        switch transport {
        case .webSocket: webSocket(server: server, identity: identity)
        case .eventSource: eventSource(server: server, identity: identity)
        }
    }

    private static func request(for transport: ActivityTransport, server: ConnectedServer, identity: ClientIdentity, upgradeScheme: Bool) throws -> URLRequest {
        var components = URLComponents(url: server.baseURL, resolvingAgainstBaseURL: false)!
        if upgradeScheme {
            components.scheme = components.scheme == "https" ? "wss" : "ws"
        }
        components.path = transport.path
        components.queryItems = [URLQueryItem(name: "X-Plex-Token", value: server.accessToken)]
        guard let url = components.url else { throw NotificationTransportError.badURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        for (name, value) in identity.headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        // Plain requests send the token as a header; do the same on the
        // upgrade so the socket is authenticated the same way they are.
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

    private static func webSocket(server: ConnectedServer, identity: ClientIdentity) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let request: URLRequest
            do {
                request = try self.request(for: .webSocket, server: server, identity: identity, upgradeScheme: true)
            } catch {
                continuation.finish(throwing: error)
                return
            }
            log.info("websocket connecting to \(request.url?.host() ?? "?", privacy: .public)")

            let session = URLSession(configuration: .ephemeral)
            let task = session.webSocketTask(with: request)
            task.resume()

            // A pong proves the handshake completed; there's no delegate here.
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
                            continuation.yield(.message(RawNotification(eventName: nil, data: text)))
                        case .data(let data):
                            log.debug("websocket binary frame \(data.count) bytes")
                            continuation.yield(.message(RawNotification(eventName: nil, data: String(decoding: data, as: UTF8.self))))
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

    private static func eventSource(server: ConnectedServer, identity: ClientIdentity) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let request: URLRequest
            do {
                var built = try self.request(for: .eventSource, server: server, identity: identity, upgradeScheme: false)
                built.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                built.timeoutInterval = .infinity
                request = built
            } catch {
                continuation.finish(throwing: error)
                return
            }
            log.info("eventsource connecting to \(request.url?.host() ?? "?", privacy: .public)")

            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = .infinity
            configuration.timeoutIntervalForResource = .infinity
            let session = URLSession(configuration: configuration)

            let reader = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    if let http = response as? HTTPURLResponse {
                        log.info("eventsource HTTP \(http.statusCode) \(http.value(forHTTPHeaderField: "Content-Type") ?? "", privacy: .public)")
                        guard (200..<300).contains(http.statusCode) else {
                            throw NotificationTransportError.status(http.statusCode)
                        }
                    }
                    continuation.yield(.opened)
                    var eventName: String?
                    var data: [String] = []
                    for try await line in bytes.lines {
                        if line.isEmpty {
                            if !data.isEmpty {
                                log.debug("eventsource event \(eventName ?? "-", privacy: .public)")
                                continuation.yield(.message(RawNotification(eventName: eventName, data: data.joined(separator: "\n"))))
                            }
                            eventName = nil
                            data = []
                        } else if line.hasPrefix("event:") {
                            eventName = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                        } else if line.hasPrefix("data:") {
                            data.append(line.dropFirst(5).trimmingCharacters(in: .whitespaces))
                        }
                        // `id:`, `retry:`, and comment lines are ignored.
                    }
                    log.info("eventsource ended")
                    continuation.finish(throwing: NotificationTransportError.closed)
                } catch {
                    if !Task.isCancelled {
                        log.error("eventsource failed: \(error.localizedDescription, privacy: .public)")
                    }
                    continuation.finish(throwing: Task.isCancelled ? CancellationError() : error)
                }
            }

            continuation.onTermination = { _ in
                reader.cancel()
                session.invalidateAndCancel()
            }
        }
    }
}
