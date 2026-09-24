import Foundation
import Observation

@MainActor
@Observable
final class MediaQueryStore {
    var query = MediaQuery()

    /// Section keys mean something only per server, so details are cached per
    /// server and the query starts over when the server changes.
    private(set) var serverID = ""
    private(set) var detailsByServer: [String: [String: SectionDetails]] = [:]
    private(set) var loadingKey: String?
    private(set) var errorMessage: String?

    private(set) var valuesByServer: [String: [String: [MediaFilterValue]]] = [:]
    private(set) var loadingValues: Set<String> = []

    var selectedItemID: Int?
    var showsItemInfo = false

    private let http: PlexHTTP
    @ObservationIgnored private var generation = 0

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

    func serverChanged(to id: String) {
        guard id != serverID else { return }
        serverID = id
        query = MediaQuery()
        errorMessage = nil
    }

    func reset() {
        generation += 1
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

    func sectionChanged() {
        var fresh = MediaQuery()
        fresh.sectionKey = query.sectionKey
        fresh.type = details(server: serverID, section: query.sectionKey)?.types.first?.number ?? 0
        query = fresh
    }

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

    func loadDetails(section sectionKey: String, on server: ConnectedServer) async {
        let machineID = server.machineID
        let generation = generation
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
            guard generation == self.generation else { return }
            guard response.status == 200 else {
                errorMessage = "The server answered HTTP \(response.status) for this library's details."
                return
            }
            let body = response.body
            let details = await Task.detached(priority: .userInitiated) {
                JSONNodeParser.parse(body).map(SectionDetails.init(root:))
            }.value
            guard generation == self.generation else { return }
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
            guard generation == self.generation else { return }
            errorMessage = (error as? URLError)?.shortDescription ?? error.localizedDescription
        }
    }

    func values(for filter: MediaFilter) -> [MediaFilterValue]? {
        valuesByServer[serverID]?[filter.valuesKey]
    }

    func isLoadingValues(for filter: MediaFilter) -> Bool {
        loadingValues.contains("\(serverID)/\(filter.valuesKey)")
    }

    func loadValues(for filter: MediaFilter, on server: ConnectedServer) async {
        let machineID = server.machineID
        let generation = generation
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
        guard generation == self.generation else { return }
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
