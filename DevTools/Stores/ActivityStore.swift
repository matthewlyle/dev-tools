import Foundation
import Observation

@MainActor
@Observable
final class ActivityStore {
    enum Status: Equatable {
        case disconnected
        case connecting
        case connected
        case reconnecting(attempt: Int, delay: Int)
        case failed(String)

        var isActive: Bool {
            switch self {
            case .connecting, .connected, .reconnecting: true
            case .disconnected, .failed: false
            }
        }
    }

    static let capacity = 2000

    private(set) var status: Status = .disconnected
    private(set) var server: ConnectedServer?
    private(set) var events: [NotificationEvent] = []
    private(set) var receivedCount = 0
    private(set) var lastError: String?
    private(set) var typeCounts: [String: Int] = [:]
    var hiddenTypes: Set<String> = []
    var selectedEventID: UUID?

    var isPaused = false {
        didSet {
            if !isPaused, !pausedBuffer.isEmpty {
                append(pausedBuffer)
                pausedBuffer.removeAll()
            }
        }
    }
    private(set) var pausedCount = 0
    private var pausedBuffer: [NotificationEvent] = []

    private let identity: ClientIdentity
    private var connection: Task<Void, Never>?

    init(identity: ClientIdentity) {
        self.identity = identity
    }

    var visibleEvents: [NotificationEvent] {
        hiddenTypes.isEmpty ? events : events.filter { !hiddenTypes.contains($0.type) }
    }

    var selectedEvent: NotificationEvent? {
        guard let selectedEventID else { return nil }
        return events.first { $0.id == selectedEventID }
    }

    func connect(to server: ConnectedServer) {
        connection?.cancel()
        self.server = server
        status = .connecting
        receivedCount = 0
        lastError = nil
        let identity = identity

        connection = Task { [weak self] in
            var attempt = 0
            while !Task.isCancelled {
                do {
                    let stream = NotificationTransport.stream(server: server, identity: identity)
                    for try await event in stream {
                        guard let self else { return }
                        switch event {
                        case .opened:
                            attempt = 0
                            self.status = .connected
                        case .message(let message):
                            self.status = .connected
                            self.receivedCount += 1
                            self.receive(message)
                        }
                    }
                    throw NotificationTransportError.closed
                } catch is CancellationError {
                    return
                } catch {
                    guard let self, !Task.isCancelled else { return }
                    self.lastError = error.localizedDescription
                    attempt += 1
                    if attempt > 8 {
                        self.status = .failed(error.localizedDescription)
                        return
                    }
                    let delay = min(1 << (attempt - 1), 30)
                    self.status = .reconnecting(attempt: attempt, delay: delay)
                    try? await Task.sleep(for: .seconds(delay))
                }
            }
        }
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        status = .disconnected
    }

    func clear() {
        events.removeAll()
        pausedBuffer.removeAll()
        pausedCount = 0
        typeCounts.removeAll()
        selectedEventID = nil
    }

    func toggle(type: String) {
        if hiddenTypes.contains(type) { hiddenTypes.remove(type) } else { hiddenTypes.insert(type) }
    }

    private func receive(_ text: String) {
        let event = NotificationEvent.make(raw: text)
        if isPaused {
            pausedBuffer.append(event)
            if pausedBuffer.count > Self.capacity { pausedBuffer.removeFirst() }
            pausedCount = pausedBuffer.count
        } else {
            append([event])
        }
    }

    private func append(_ incoming: [NotificationEvent]) {
        for event in incoming {
            typeCounts[event.type, default: 0] += 1
        }
        events.insert(contentsOf: incoming.reversed(), at: 0)
        if events.count > Self.capacity {
            events.removeLast(events.count - Self.capacity)
        }
        pausedCount = 0
    }
}
