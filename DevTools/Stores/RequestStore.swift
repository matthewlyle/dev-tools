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

    /// A request's path + params for display: the server's token masked
    /// wherever it appears, plus any `X-Plex-Token=…` typed into the path.
    func redactedSummary(of request: PlexRequest, token: String?) -> String {
        redacted(request.summary, token: token)
            .replacing(/X-Plex-Token=[^&\s]+/) { _ in "X-Plex-Token=\(Self.mask)" }
    }

    func shouldMask(attributeNamed name: String) -> Bool {
        Self.tokenAttributeNames.contains(name)
    }

    private(set) var pathFocusToken = 0

    private(set) var parametersRevealToken = 0

    /// Bumped by ⌘S; the request bar presents the save sheet.
    private(set) var saveRequestToken = 0

    func requestSave() {
        saveRequestToken &+= 1
    }

    private(set) var backStack: [PlexRequest] = []
    private(set) var forwardStack: [PlexRequest] = []
    private var lastSent: PlexRequest?

    private let http: PlexHTTP
    private let memory: ValueMemory
    private var sendTask: Task<Void, Never>?

    private static let historyFile = "history.json"
    private static let historyCap = 500

    init(http: PlexHTTP, memory: ValueMemory) {
        self.http = http
        self.memory = memory
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

    /// Re-runs a request chosen from history: shows the response without
    /// recording a new history entry for the replay.
    func replay(_ entry: HistoryEntry, on server: ConnectedServer) {
        load(entry)
        perform(current, on: server, recordHistory: false)
    }

    func open(path: String, on server: ConnectedServer) {
        editingSavedID = nil
        current.path = path
        current.query = []
        send(to: server)
    }

    func open(_ operation: SpecOperation, path: String, on server: ConnectedServer) {
        editingSavedID = nil
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
        editingSavedID = nil
        current = previous
        perform(previous, on: server)
    }

    func goForward(on server: ConnectedServer) {
        guard let next = forwardStack.popLast() else { return }
        if let lastSent { backStack.append(lastSent) }
        editingSavedID = nil
        current = next
        perform(next, on: server)
    }

    private func perform(_ request: PlexRequest, on server: ConnectedServer, recordHistory: Bool = true) {
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
                if recordHistory { record(request, server: server, status: result.status, duration: result.duration, error: nil) }
                isSending = false
                let parsed = await ResponseDocument.make(from: result)
                guard !Task.isCancelled else { return }
                document = parsed
                if let root = parsed.tree { memory.record(root: root, serverID: server.machineID) }
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
                if recordHistory { record(request, server: server, status: nil, duration: nil, error: message) }
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

    struct SectionOption: Identifiable, Hashable, Sendable {
        var id: String { key }
        let key: String
        let title: String
        let type: String
    }

    private(set) var sectionsByServer: [String: [SectionOption]] = [:]

    func sections(for server: ConnectedServer) -> [SectionOption] {
        sectionsByServer[server.machineID] ?? []
    }

    /// Warm the section cache so placeholder pickers fill without a fetch. A
    /// miss fetches; an existing cache is kept unless `force`. A failed fetch
    /// returns empty and is never cached, so it retries next time.
    func preloadSections(on server: ConnectedServer, force: Bool = false) async {
        if !force, sectionsByServer[server.machineID]?.isEmpty == false { return }
        let fetched = await fetchSections(on: server)
        guard !fetched.isEmpty else { return }
        sectionsByServer[server.machineID] = fetched
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

    /// Returns the workspace to a clean request: default path, no response,
    /// no navigation history. Used when the visible section changes so stale
    /// results don't linger under a different tab.
    func reset() {
        cancel()
        current = PlexRequest(path: "/")
        current.accept = acceptFormat
        response = nil
        document = nil
        errorMessage = nil
        lastSent = nil
        backStack = []
        forwardStack = []
        editingSavedID = nil
    }

    func requestPathFocus() {
        pathFocusToken &+= 1
    }

    func previewURL(for server: ConnectedServer?) -> String {
        guard let server else { return "No server selected" }
        return current.url(base: server.baseURL)?.absoluteString ?? "Invalid URL"
    }

    /// The current request as a `curl` command with `$PLEX_TOKEN` in place
    /// of the credential.
    func curl(for server: ConnectedServer) -> String? {
        CurlExporter.command(for: current, base: server.baseURL, identityHeaders: http.identity.headers)
    }

    /// Adds `value` to the comma-separated query param `name`, creating the
    /// param if needed. Used by the response-shape menus.
    func appendToListParameter(_ name: String, value: String) {
        if let index = current.query.firstIndex(where: { $0.name == name }) {
            var values = current.query[index].value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard !values.contains(value) else { return }
            values.append(value)
            current.query[index].value = values.joined(separator: ",")
            current.query[index].enabled = true
        } else {
            current.query.append(QueryParam(name: name, value: value))
        }
        revealParameters()
    }

    /// Values already in the comma-separated query param `name`.
    func listParameterValues(_ name: String) -> Set<String> {
        guard let param = current.query.first(where: { $0.name == name }) else { return [] }
        return Set(param.value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
    }

    /// Restores the path, params, and headers; the response format follows
    /// the app-wide setting, not what the request was last sent with.
    func load(_ request: PlexRequest) {
        editingSavedID = nil
        current = request
        current.accept = acceptFormat
    }

    /// The saved request the bar was loaded from, if any. Edits keep it;
    /// navigating anywhere else ends it. ⌘S offers Update while it's set.
    private(set) var editingSavedID: UUID?

    func load(saved item: SavedRequest) {
        load(item.request)
        editingSavedID = item.id
    }

    func load(_ entry: HistoryEntry) {
        load(entry.request)
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
