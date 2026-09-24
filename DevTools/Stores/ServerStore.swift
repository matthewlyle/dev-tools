import Foundation
import Observation

@MainActor
@Observable
final class ServerStore {
    struct Entry: Identifiable, Hashable {
        var id: String { resource.clientIdentifier }
        let resource: PlexResource
        var probes: [ProbeResult] = []
        /// The probe whose answer is kept; an older one's is dropped.
        fileprivate var pendingProbe: Int?

        init(resource: PlexResource) {
            self.resource = resource
        }

        var isProbing: Bool { pendingProbe != nil }
        var reachable: [ProbeResult] { probes.filter(\.outcome.isOK) }
    }

    private struct Snapshot: Codable {
        var resources: [PlexResource]
        var selectedID: String?
        var ownerAvatars: [String: URL]?
    }

    private static let snapshotFile = "servers.json"

    private(set) var entries: [Entry] = []
    private(set) var ownerAvatars: [Int: URL] = [:]
    var selectedID: String? {
        didSet { persist() }
    }
    private(set) var isRefreshing = false
    var errorMessage: String?

    private let plexTV: PlexTVClient
    private let prober: ConnectionProber
    /// Bumped by whatever makes an in-flight refresh's answer stale: a newer
    /// refresh, sign-out.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var probeSequence = 0

    init(plexTV: PlexTVClient, prober: ConnectionProber) {
        self.plexTV = plexTV
        self.prober = prober
        if let snapshot = AppSupportStore.load(Snapshot.self, name: Self.snapshotFile) {
            entries = snapshot.resources.map { Entry(resource: $0) }
            selectedID = snapshot.selectedID
            ownerAvatars = Dictionary(uniqueKeysWithValues: (snapshot.ownerAvatars ?? [:]).compactMap { key, url in Int(key).map { ($0, url) } })
            if snapshot.resources.contains(where: { $0.accessToken != nil }) { persist() }
        }
    }

    var selected: Entry? {
        guard let selectedID else { return nil }
        return entries.first { $0.id == selectedID }
    }

    func entry(id: String) -> Entry? {
        entries.first { $0.id == id }
    }

    var sortedEntries: [Entry] {
        func rank(_ entry: Entry) -> Int {
            if let probe = activeProbe(for: entry) {
                switch probe.connection.kind {
                case .local: return 0
                case .remote: return 1
                case .relay: return 2
                }
            }
            return entry.probes.isEmpty ? 3 : 4
        }
        return entries.sorted { lhs, rhs in
            let l = rank(lhs), r = rank(rhs)
            if l != r { return l < r }
            return lhs.resource.name.localizedStandardCompare(rhs.resource.name) == .orderedAscending
        }
    }

    func refresh(token: String) async {
        generation += 1
        let generation = generation
        isRefreshing = true
        defer { if generation == self.generation { isRefreshing = false } }
        errorMessage = nil

        async let avatarsTask = plexTV.friendAvatars(token: token)
        do {
            let servers = try await plexTV.resources(token: token)
                .filter(\.isServer)
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            guard generation == self.generation else { return }
            let previous = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
            entries = servers.map { resource in
                var entry = Entry(resource: resource)
                entry.probes = previous[resource.clientIdentifier]?.probes ?? []
                return entry
            }
            if let selectedID, !entries.contains(where: { $0.id == selectedID }) {
                self.selectedID = nil
            }
            if selectedID == nil { selectedID = entries.first?.id }
        } catch {
            guard generation == self.generation else { return }
            errorMessage = error.localizedDescription
        }
        let avatars = try? await avatarsTask
        guard generation == self.generation else { return }
        if let avatars { ownerAvatars = avatars }
        persist()

        await probeAll()
    }

    func ownerAvatar(for resource: PlexResource) -> URL? {
        guard let ownerId = resource.ownerId else { return nil }
        return ownerAvatars[ownerId] ?? resource.ownerAvatarURL
    }

    func probeAll() async {
        await withTaskGroup(of: Void.self) { group in
            for entry in entries {
                group.addTask { await self.probe(id: entry.id) }
            }
        }
    }

    func probe(id: String) async {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        probeSequence += 1
        let sequence = probeSequence
        entries[index].pendingProbe = sequence
        let results = await prober.probeAll(entries[index].resource)
        guard let current = entries.firstIndex(where: { $0.id == id }),
              entries[current].pendingProbe == sequence
        else { return }
        entries[current].probes = results
        entries[current].pendingProbe = nil
    }

    func activeProbe(for entry: Entry) -> ProbeResult? {
        entry.reachable.first
    }

    func connectedServer(for entry: Entry) -> ConnectedServer? {
        guard let probe = activeProbe(for: entry),
              let url = probe.connection.url,
              let token = entry.resource.accessToken
        else { return nil }
        return ConnectedServer(
            machineID: entry.resource.clientIdentifier,
            name: entry.resource.name,
            baseURL: url,
            accessToken: token,
            connection: probe.connection,
            owned: entry.resource.owned
        )
    }

    func clear() {
        generation += 1
        isRefreshing = false
        errorMessage = nil
        entries = []
        ownerAvatars = [:]
        selectedID = nil
        persist()
    }

    private func persist() {
        AppSupportStore.save(
            Snapshot(
                resources: entries.map(\.resource),
                selectedID: selectedID,
                ownerAvatars: Dictionary(uniqueKeysWithValues: ownerAvatars.map { (String($0.key), $0.value) })
            ),
            name: Self.snapshotFile
        )
    }
}
