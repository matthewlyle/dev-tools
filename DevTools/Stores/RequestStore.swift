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
    /// Set by the request bar's ⓘ; the docs popover is presented from the
    /// response view's own SwiftUI tree, since the request bar itself is
    /// hosted inside the response text view where popovers can't present.
    var showingDocs = false

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

    /// Set by Focus Path and consumed by the request bar, which may not be on
    /// screen yet: a compact width pushes it after the request.
    var pathFocusPending = false

    /// Bumped by ⌘S; the request bar presents the save sheet.
    private(set) var saveRequestToken = 0

    func requestSave() {
        saveRequestToken &+= 1
    }

    private(set) var backStack: [PlexRequest] = []
    private(set) var forwardStack: [PlexRequest] = []
    private(set) var lastSent: PlexRequest?

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

    /// Off in Media: its results come from the builder's form, and going back
    /// would show a query the form no longer holds.
    var recordsNavigation = true

    func send(to server: ConnectedServer) {
        let request = current
        if recordsNavigation, let lastSent, lastSent != request {
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

    /// Loads the operation's required parameters. Sends only when they all
    /// have values; otherwise the request waits in the always-visible editor.
    func open(_ operation: SpecOperation, path: String, on server: ConnectedServer) {
        editingSavedID = nil
        current.path = path
        current.query = operation.queryParameters
            .filter(\.required)
            .map { QueryParam(name: $0.name, value: $0.suggestedValue) }
        discardResponse(unlessFor: current)
        if current.query.allSatisfy({ !$0.value.isEmpty }) {
            send(to: server)
        }
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

    /// A value a placeholder can take, listed from the server.
    struct PlaceholderOption: Identifiable, Hashable, Sendable {
        var id: String { key }
        let key: String
        let title: String
        /// Set when options span several sources (a collection's library).
        var group: String? = nil
    }

    /// Placeholders whose values the server can list, so the placeholder
    /// sheet offers a picker instead of asking for an id from memory.
    nonisolated static let listablePlaceholders: [String] = ["sectionId", "playlistId", "collectionId", "deviceId"]

    private(set) var sectionsByServer: [String: [SectionOption]] = [:]
    private(set) var optionsByServer: [String: [String: [PlaceholderOption]]] = [:]
    private(set) var loadedOptions: [String: Set<String>] = [:]

    func sections(for server: ConnectedServer) -> [SectionOption] {
        sectionsByServer[server.machineID] ?? []
    }

    func options(for placeholder: String, server: ConnectedServer) -> [PlaceholderOption] {
        if placeholder == "sectionId" {
            return sections(for: server).map { PlaceholderOption(key: $0.key, title: $0.title) }
        }
        return optionsByServer[server.machineID]?[placeholder] ?? []
    }

    /// Warm every listable placeholder for a server so the sheet's pickers
    /// fill without a fetch. Sections first: collections are listed per section.
    func preloadOptions(on server: ConnectedServer) async {
        await preloadSections(on: server)
        await withTaskGroup(of: Void.self) { group in
            for name in Self.listablePlaceholders where name != "sectionId" {
                group.addTask { await self.preloadOptions(for: name, on: server) }
            }
        }
    }

    /// A miss fetches; a completed fetch (even empty) is kept unless `force`;
    /// a failed fetch is not recorded, so it retries next time.
    func preloadOptions(for placeholder: String, on server: ConnectedServer, force: Bool = false) async {
        if placeholder == "sectionId" {
            await preloadSections(on: server, force: force)
            return
        }
        let machineID = server.machineID
        if !force, loadedOptions[machineID]?.contains(placeholder) == true { return }
        guard let fetched = await fetchOptions(for: placeholder, on: server) else { return }
        optionsByServer[machineID, default: [:]][placeholder] = fetched
        loadedOptions[machineID, default: []].insert(placeholder)
    }

    /// Warm the section cache. A miss fetches; an existing cache is kept
    /// unless `force`. A failed fetch returns empty and is never cached.
    func preloadSections(on server: ConnectedServer, force: Bool = false) async {
        if !force, sectionsByServer[server.machineID]?.isEmpty == false { return }
        let fetched = await fetchSections(on: server)
        guard !fetched.isEmpty else { return }
        sectionsByServer[server.machineID] = fetched
    }

    func fetchSections(on server: ConnectedServer) async -> [SectionOption] {
        guard let root = await fetchRoot("/library/sections", on: server) else { return [] }
        return root.children.compactMap { child in
            guard let key = child["key"], let title = child["title"] else { return nil }
            return SectionOption(key: key, title: title, type: child["type"] ?? "")
        }
    }

    /// `nil` means the request failed; an empty array means the server has none.
    private func fetchOptions(for placeholder: String, on server: ConnectedServer) async -> [PlaceholderOption]? {
        switch placeholder {
        case "playlistId":
            guard let root = await fetchRoot("/playlists", on: server) else { return nil }
            return Self.itemOptions(from: root)
        case "collectionId":
            await preloadSections(on: server)
            let sections = sections(for: server)
            guard !sections.isEmpty else { return [] }
            var failed = false
            var options: [PlaceholderOption] = []
            await withTaskGroup(of: [PlaceholderOption]?.self) { group in
                for section in sections {
                    group.addTask {
                        let root = await self.fetchRoot("/library/sections/\(section.key)/collections", on: server)
                        return root.map { Self.itemOptions(from: $0, group: section.title) }
                    }
                }
                for await result in group {
                    if let result { options += result } else { failed = true }
                }
            }
            return failed && options.isEmpty ? nil : options
        case "deviceId":
            guard let root = await fetchRoot("/media/grabbers/devices", on: server) else { return nil }
            return Self.deviceOptions(from: root)
        default:
            return nil
        }
    }

    /// Library items (playlists, collections): `ratingKey` is the id.
    nonisolated static func itemOptions(from root: Node, group: String? = nil) -> [PlaceholderOption] {
        root.children.compactMap { item in
            guard let key = item["ratingKey"] else { return nil }
            return PlaceholderOption(key: key, title: item["title"] ?? key, group: group)
        }
    }

    /// Tuner devices: the id attribute and a display name vary by grabber, so
    /// fall back through the names Plex uses.
    nonisolated static func deviceOptions(from root: Node) -> [PlaceholderOption] {
        root.children.compactMap { device in
            guard let key = device["key"] ?? device["uuid"] ?? device["id"] else { return nil }
            let title = device["title"]
                ?? [device["make"], device["model"]].compactMap { $0 }.joined(separator: " ")
            return PlaceholderOption(key: key, title: title.isEmpty ? key : title)
        }
    }

    private func fetchRoot(_ path: String, on server: ConnectedServer) async -> Node? {
        var request = PlexRequest(path: path)
        request.accept = .json
        guard let response = try? await http.send(request, to: server), response.status == 200 else { return nil }
        return JSONNodeParser.parse(response.body)
    }

    func cancel() {
        sendTask?.cancel()
        sendTask = nil
        isSending = false
    }

    /// Returns the workspace to a clean request: default path, no response,
    /// no navigation history.
    func reset() {
        cancel()
        apply(Workspace())
    }

    /// One section's request and what it produced, kept while another
    /// section has the workspace.
    private struct Workspace {
        var current = PlexRequest(path: "/")
        var response: PlexResponse?
        var document: ResponseDocument?
        var errorMessage: String?
        var lastSent: PlexRequest?
        var backStack: [PlexRequest] = []
        var forwardStack: [PlexRequest] = []
        var editingSavedID: UUID?
    }

    private var parked: [String: Workspace] = [:]

    /// Sections share this one workspace, so a switch parks the outgoing
    /// section's and restores the incoming one's: each keeps its last
    /// request and response, and a pushed detail still has it on return.
    /// A send in flight is cancelled; its result would land in the wrong
    /// section.
    func switchWorkspace(from outgoing: String, to incoming: String) {
        cancel()
        parked[outgoing] = Workspace(
            current: current, response: response, document: document, errorMessage: errorMessage,
            lastSent: lastSent, backStack: backStack, forwardStack: forwardStack, editingSavedID: editingSavedID
        )
        apply(parked.removeValue(forKey: incoming) ?? Workspace())
    }

    /// Every section's workspace, gone: they belong to the server they ran on.
    func resetAllWorkspaces() {
        parked.removeAll()
        reset()
    }

    private func apply(_ workspace: Workspace) {
        current = workspace.current
        current.accept = acceptFormat
        response = workspace.response
        document = workspace.document
        errorMessage = workspace.errorMessage
        lastSent = workspace.lastSent
        backStack = workspace.backStack
        forwardStack = workspace.forwardStack
        editingSavedID = workspace.editingSavedID
        showingDocs = false
        pathFocusPending = false
    }

    func requestPathFocus() {
        pathFocusPending = true
    }

    func previewURL(for server: ConnectedServer?) -> String {
        guard let server else { return "No server selected" }
        return current.url(base: server.baseURL)?.absoluteString ?? "Invalid URL"
    }

    /// The current request's URL, safe to paste anywhere: the token travels
    /// as a header, never in it.
    func shareableURL(for server: ConnectedServer) -> String? {
        current.url(base: server.baseURL)?.absoluteString
    }

    /// The current request as a `curl` command with `$PLEX_TOKEN` in place
    /// of the credential.
    func curl(for server: ConnectedServer) -> String? {
        CurlExporter.command(for: current, base: server.baseURL, identityHeaders: http.identity.headers)
    }

    /// Restores the path, params, and headers; the response format follows
    /// the app-wide setting, not what the request was last sent with.
    func load(_ request: PlexRequest) {
        editingSavedID = nil
        current = request
        current.accept = acceptFormat
        discardResponse(unlessFor: current)
    }

    /// Opening a different request drops the last one's response, which
    /// would otherwise show under it until the send lands. Re-running the
    /// same request keeps it readable.
    private func discardResponse(unlessFor request: PlexRequest) {
        guard request.summary != lastSent?.summary else { return }
        cancel()
        response = nil
        document = nil
        errorMessage = nil
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

    func deleteHistoryEntry(_ id: HistoryEntry.ID) {
        clearHistory { $0.id == id }
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
