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
    private(set) var selectedEvent: NotificationEvent?

    /// Resolved item titles for rows whose payload names the item by key
    /// alone. `requestedTitles` holds every key ever asked for, in flight,
    /// resolved or failed, so a playing session's repeated frames fetch once
    /// and a failure isn't retried until the events are cleared.
    private(set) var titles: [TitleKey: String] = [:]
    private var requestedTitles: Set<TitleKey> = []

    struct TitleKey: Hashable {
        let server: String
        let ratingKey: String
    }

    private let http: PlexHTTP
    private var connection: Task<Void, Never>?

    init(http: PlexHTTP) {
        self.http = http
    }

    var visibleEvents: [NotificationEvent] {
        hiddenTypes.isEmpty ? events : events.filter { !hiddenTypes.contains($0.type) }
    }

    /// The selection holds the event itself rather than looking it up in the
    /// buffer, so views reading it aren't invalidated by every incoming frame
    /// and the ring buffer can trim it without closing the inspector.
    var selectedEventID: UUID? {
        get { selectedEvent?.id }
        set {
            guard newValue != selectedEvent?.id else { return }
            selectedEvent = newValue.flatMap { id in events.first { $0.id == id } }
        }
    }

    /// The looked-up title of the item an event names by key, once resolved.
    func title(for event: NotificationEvent) -> String? {
        guard let server, let ratingKey = event.titleKey else { return nil }
        return titles[TitleKey(server: server.machineID, ratingKey: ratingKey)]
    }

    func connect(to server: ConnectedServer) {
        connection?.cancel()
        self.server = server
        status = .connecting
        receivedCount = 0
        lastError = nil
        let identity = http.identity

        connection = Task { [weak self] in
            var attempt = 0
            while !Task.isCancelled {
                do {
                    let stream = NotificationTransport.stream(server: server, identity: identity)
                    for try await element in stream {
                        guard let self else { return }
                        // Observation notifies on every assignment, equal or
                        // not, and every status reader would redraw per frame.
                        if self.status != .connected { self.status = .connected }
                        switch element {
                        case .opened:
                            attempt = 0
                        case .message(let event):
                            self.receivedCount += 1
                            self.append(event)
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
        typeCounts.removeAll()
        selectedEvent = nil
        titles.removeAll()
        requestedTitles.removeAll()
    }

    func toggle(type: String) {
        if hiddenTypes.contains(type) { hiddenTypes.remove(type) } else { hiddenTypes.insert(type) }
    }

    private func append(_ event: NotificationEvent) {
        typeCounts[event.type, default: 0] += 1
        events.insert(event, at: 0)
        if events.count > Self.capacity {
            events.removeLast(events.count - Self.capacity)
        }
        if let ratingKey = event.titleKey { resolveTitle(ratingKey) }
    }

    /// Internal lookups pin JSON like the app's other background fetches;
    /// the Accept setting is for the requests the user sends.
    private func resolveTitle(_ ratingKey: String) {
        guard let server else { return }
        let key = TitleKey(server: server.machineID, ratingKey: ratingKey)
        guard requestedTitles.insert(key).inserted else { return }
        Task { [http, weak self] in
            var request = PlexRequest(path: "/library/metadata/\(ratingKey)")
            request.accept = .json
            guard let response = try? await http.send(request, to: server), response.status == 200 else { return }
            let body = response.body
            let title = await Task.detached(priority: .utility) {
                JSONNodeParser.parse(body).flatMap(NotificationEvent.itemTitle(metadata:))
            }.value
            guard let self, let title, self.requestedTitles.contains(key) else { return }
            self.titles[key] = title
        }
    }
}
