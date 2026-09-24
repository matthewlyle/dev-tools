import Foundation
import Observation

@MainActor
@Observable
final class MediaQueryStore {
    /// The query being built. Kept here rather than in the view so it
    /// survives switching sections and servers.
    var query = MediaQuery()

    /// The server the current query belongs to. Section keys are only
    /// meaningful per server, so details are cached per server too and the
    /// query starts over when the server changes.
    private(set) var serverID = ""
    private(set) var detailsByServer: [String: [String: SectionDetails]] = [:]
    private(set) var loadingKey: String?
    private(set) var errorMessage: String?

    /// Possible values per filter endpoint, keyed by server then the
    /// filter's `valuesKey` (which already carries the type). `nil` while
    /// unloaded; an empty list is a real answer.
    private(set) var valuesByServer: [String: [String: [MediaFilterValue]]] = [:]
    private(set) var loadingValues: Set<String> = []

    /// The poster selected in the results, and whether its inspector is
    /// open. Here rather than in the results view because the detail pane
    /// hosts one inspector for every section.
    var selectedItemID: Int?
    var showsItemInfo = false

    private let http: PlexHTTP

    init(http: PlexHTTP) {
        self.http = http
    }

    private func details(server: String, section: String) -> SectionDetails? {
        detailsByServer[server]?[section]
    }

    var currentDetails: SectionDetails? {
        query.hasSection ? details(server: serverID, section: query.sectionKey) : nil
    }

    var currentType: MediaType? {
        currentDetails?.types.first { $0.number == query.type }
    }

    var isLoading: Bool {
        query.hasSection && loadingKey == "\(serverID)/\(query.sectionKey)"
    }

    /// Called when the builder is shown for a server: a different server
    /// gets a fresh query, since its section keys mean something else.
    func serverChanged(to id: String) {
        guard id != serverID else { return }
        serverID = id
        query = MediaQuery()
        errorMessage = nil
    }

    func reset() {
        serverID = ""
        query = MediaQuery()
        detailsByServer = [:]
        valuesByServer = [:]
        loadingKey = nil
        loadingValues = []
        errorMessage = nil
        selectedItemID = nil
        showsItemInfo = false
    }

    /// Called after `query.sectionKey` changes: start over for that library,
    /// defaulting to its first type when the details are already known. The
    /// replacement is built whole and assigned once so observers see one
    /// change.
    func sectionChanged() {
        var fresh = MediaQuery()
        fresh.sectionKey = query.sectionKey
        fresh.type = details(server: serverID, section: query.sectionKey)?.types.first?.number ?? 0
        query = fresh
    }

    /// Called after `query.type` changes: drop filters, sorts, and grouping
    /// that belong to another type so every picker keeps a valid selection.
    func typeChanged() {
        guard let type = currentType else { return }
        let fields = Set(type.fields.map(\.key))
        let sorts = Set(type.sorts.map(\.key))
        var pruned = query
        pruned.pruneTerms(keepingFields: fields)
        pruned.sorts.removeAll { !sorts.contains($0.key) }
        if !fields.contains(pruned.group) { pruned.group = "" }
        if pruned != query { query = pruned }
    }

    /// Fetches a section's types, fields, and sorts once; a failed fetch is
    /// not cached so it retries next time.
    func loadDetails(section sectionKey: String, on server: ConnectedServer) async {
        let machineID = server.machineID
        guard details(server: machineID, section: sectionKey) == nil else {
            ensureValidType()
            return
        }
        loadingKey = "\(machineID)/\(sectionKey)"
        errorMessage = nil
        defer { loadingKey = nil }

        var request = PlexRequest(path: "/library/sections/\(sectionKey)")
        request.query = [QueryParam(name: "includeDetails", value: "1")]
        request.accept = .json
        do {
            let response = try await http.send(request, to: server)
            guard response.status == 200 else {
                errorMessage = "The server answered HTTP \(response.status) for this library's details."
                return
            }
            let body = response.body
            let details = await Task.detached(priority: .userInitiated) {
                JSONNodeParser.parse(body).map(SectionDetails.init(root:))
            }.value
            guard let details else {
                errorMessage = "The library details weren't valid JSON."
                return
            }
            detailsByServer[machineID, default: [:]][sectionKey] = details
            ensureValidType()
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            errorMessage = (error as? URLError)?.shortDescription ?? error.localizedDescription
        }
    }

    func values(for filter: MediaFilter) -> [MediaFilterValue]? {
        valuesByServer[serverID]?[filter.valuesKey]
    }

    func isLoadingValues(for filter: MediaFilter) -> Bool {
        loadingValues.contains("\(serverID)/\(filter.valuesKey)")
    }

    /// Fetches a filter's possible values once per server; a failed fetch is
    /// not cached so it retries next time.
    func loadValues(for filter: MediaFilter, on server: ConnectedServer) async {
        let machineID = server.machineID
        let key = "\(machineID)/\(filter.valuesKey)"
        guard valuesByServer[machineID]?[filter.valuesKey] == nil, !loadingValues.contains(key) else { return }
        loadingValues.insert(key)
        defer { loadingValues.remove(key) }

        var request = PlexRequest(path: filter.valuesKey)
        request.accept = .json
        guard let response = try? await http.send(request, to: server), response.status == 200 else { return }
        let body = response.body
        let values = await Task.detached(priority: .userInitiated) {
            JSONNodeParser.parse(body).map(MediaFilterValue.parse(root:)) ?? []
        }.value
        valuesByServer[machineID, default: [:]][filter.valuesKey] = values
    }

    private func ensureValidType() {
        guard let details = currentDetails,
              !details.types.contains(where: { $0.number == query.type }),
              let first = details.types.first
        else { return }
        query.type = first.number
    }
}
