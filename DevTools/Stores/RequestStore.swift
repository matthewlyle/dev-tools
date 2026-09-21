import Foundation
import Observation

@MainActor
@Observable
final class RequestStore {
    var current = PlexRequest(path: "/")
    private(set) var response: PlexResponse?
    private(set) var document: ResponseDocument?
    private(set) var errorMessage: String?
    private(set) var isSending = false
    private(set) var history: [HistoryEntry] = []

    var acceptFormat: AcceptFormat {
        didSet {
            UserDefaults.standard.set(acceptFormat.rawValue, forKey: Self.acceptKey)
            current.accept = acceptFormat
        }
    }

    /// Tokens are never shown: not in URLs, copies, history, headers, or
    /// token-like response values. There is deliberately no way to reveal them.
    static let mask = "••••••••"
    private static let acceptKey = "acceptFormat"

    /// Attribute names whose values are credentials in Plex payloads.
    static let tokenAttributeNames: Set<String> = [
        "token", "authToken", "accessToken", "authenticationToken", "transientToken", "X-Plex-Token",
    ]

    func redacted(_ value: String, token: String?) -> String {
        guard let token, !token.isEmpty else { return value }
        return value.replacingOccurrences(of: token, with: Self.mask)
    }

    func shouldMask(attributeNamed name: String) -> Bool {
        Self.tokenAttributeNames.contains(name)
    }

    private(set) var pathFocusToken = 0

    private(set) var parametersRevealToken = 0

    private(set) var backStack: [PlexRequest] = []
    private(set) var forwardStack: [PlexRequest] = []
    private var lastSent: PlexRequest?

    private let http: PlexHTTP
    private var sendTask: Task<Void, Never>?

    private static let historyFile = "history.json"
    private static let historyCap = 500

    init(http: PlexHTTP) {
        self.http = http
        acceptFormat = UserDefaults.standard.string(forKey: Self.acceptKey).flatMap(AcceptFormat.init(rawValue:)) ?? .json
        current.accept = acceptFormat
        history = AppSupportStore.load([HistoryEntry].self, name: Self.historyFile) ?? []
    }

    func implicitHeaders(for server: ConnectedServer?) -> [(name: String, value: String)] {
        var headers = http.identity.headers.sorted { $0.key < $1.key }.map { (name: $0.key, value: $0.value) }
        headers.insert((name: "Accept", value: current.accept.rawValue), at: 0)
        if server != nil {
            headers.append((name: "X-Plex-Token", value: Self.mask))
        }
        return headers
    }

    func send(to server: ConnectedServer) {
        let request = current
        if let lastSent, lastSent != request {
            backStack.append(lastSent)
            forwardStack.removeAll()
        }
        perform(request, on: server)
    }

    func open(path: String, on server: ConnectedServer) {
        current.path = path
        current.query = []
        send(to: server)
    }

    func open(_ operation: SpecOperation, path: String, on server: ConnectedServer) {
        current.path = path
        current.query = operation.queryParameters
            .filter(\.required)
            .map { QueryParam(name: $0.name, value: $0.suggestedValue) }
        if current.query.contains(where: { $0.value.isEmpty }) {
            revealParameters()
        } else {
            send(to: server)
        }
    }

    func revealParameters() {
        parametersRevealToken &+= 1
    }

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    func goBack(on server: ConnectedServer) {
        guard let previous = backStack.popLast() else { return }
        if let lastSent { forwardStack.append(lastSent) }
        current = previous
        perform(previous, on: server)
    }

    func goForward(on server: ConnectedServer) {
        guard let next = forwardStack.popLast() else { return }
        if let lastSent { backStack.append(lastSent) }
        current = next
        perform(next, on: server)
    }

    private func perform(_ request: PlexRequest, on server: ConnectedServer) {
        sendTask?.cancel()
        isSending = true
        errorMessage = nil
        lastSent = request

        sendTask = Task { [http] in
            do {
                let result = try await http.send(request, to: server)
                guard !Task.isCancelled else { return }
                response = result
                document = nil
                record(request, server: server, status: result.status, duration: result.duration, error: nil)
                isSending = false
                let parsed = await ResponseDocument.make(from: result)
                guard !Task.isCancelled else { return }
                document = parsed
            } catch is CancellationError {
                return
            } catch let error as URLError where error.code == .cancelled {
                return
            } catch {
                guard !Task.isCancelled else { return }
                response = nil
                document = nil
                let message = (error as? URLError)?.shortDescription ?? error.localizedDescription
                errorMessage = message
                record(request, server: server, status: nil, duration: nil, error: message)
                isSending = false
            }
        }
    }

    func setHeader(_ name: String, to value: String?) {
        if let value, !value.isEmpty {
            if let index = current.headers.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                current.headers[index].value = value
                current.headers[index].enabled = true
            } else {
                current.headers.append(HeaderField(name: name, value: value))
            }
        } else {
            current.headers.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        }
    }

    var pagination: PaginationInfo? {
        guard let response, response.status == 200 else { return nil }
        return PaginationInfo(response: response, root: document?.tree)
    }

    func page(start: Int, size: Int, on server: ConnectedServer) {
        setHeader("X-Plex-Container-Start", to: String(max(start, 0)))
        setHeader("X-Plex-Container-Size", to: String(size))
        send(to: server)
    }

    struct Peek: Sendable {
        let document: ResponseDocument
        let pagination: PaginationInfo?
    }

    enum PeekError: Error, LocalizedError {
        case status(Int)

        var errorDescription: String? {
            switch self {
            case .status(let code): "HTTP \(code)"
            }
        }
    }

    func peek(path: String, on server: ConnectedServer, start: Int = 0, size: Int = 100) async throws -> Peek {
        var request = PlexRequest(path: path)
        request.accept = current.accept
        request.headers = [
            HeaderField(name: "X-Plex-Container-Start", value: String(start)),
            HeaderField(name: "X-Plex-Container-Size", value: String(size)),
        ]
        let response = try await http.send(request, to: server)
        guard response.status == 200 else { throw PeekError.status(response.status) }
        let document = await ResponseDocument.make(from: response)
        return Peek(document: document, pagination: PaginationInfo(response: response, root: document.tree))
    }

    struct SectionOption: Identifiable, Hashable, Sendable {
        var id: String { key }
        let key: String
        let title: String
        let type: String
    }

    func fetchSections(on server: ConnectedServer) async -> [SectionOption] {
        var request = PlexRequest(path: "/library/sections")
        request.accept = .json
        guard let response = try? await http.send(request, to: server), response.status == 200,
              let root = JSONNodeParser.parse(response.body)
        else { return [] }
        return root.children.compactMap { child in
            guard let key = child["key"], let title = child["title"] else { return nil }
            return SectionOption(key: key, title: title, type: child["type"] ?? "")
        }
    }

    func cancel() {
        sendTask?.cancel()
        sendTask = nil
        isSending = false
    }

    func requestPathFocus() {
        pathFocusToken &+= 1
    }

    func previewURL(for server: ConnectedServer?) -> String {
        guard let server else { return "No server selected" }
        return current.url(base: server.baseURL)?.absoluteString ?? "Invalid URL"
    }

    func load(_ entry: HistoryEntry) {
        current = entry.request
        current.accept = acceptFormat
    }

    func clearHistory(where predicate: (HistoryEntry) -> Bool) {
        history.removeAll(where: predicate)
        AppSupportStore.save(history, name: Self.historyFile)
    }

    private func record(_ request: PlexRequest, server: ConnectedServer, status: Int?, duration: Duration?, error: String?) {
        let entry = HistoryEntry(
            id: UUID(),
            request: request,
            serverID: server.machineID,
            serverName: server.name,
            status: status,
            durationMilliseconds: duration?.milliseconds,
            error: error,
            date: .now
        )
        history.insert(entry, at: 0)
        if history.count > Self.historyCap {
            history.removeLast(history.count - Self.historyCap)
        }
        AppSupportStore.save(history, name: Self.historyFile)
    }
}
