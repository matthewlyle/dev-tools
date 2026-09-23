import Foundation
import Observation

@MainActor
@Observable
final class SavedStore {
    private(set) var saved: [SavedRequest] = []

    private static let file = "saved.json"

    init() {
        saved = AppSupportStore.load([SavedRequest].self, name: Self.file) ?? []
    }

    /// Newest first, for one server.
    func items(for serverID: String) -> [SavedRequest] {
        saved.filter { $0.serverID == serverID }.sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    func add(name: String, request: PlexRequest, serverID: String) -> SavedRequest {
        let item = SavedRequest(id: UUID(), name: name, request: request, serverID: serverID, createdAt: .now)
        saved.insert(item, at: 0)
        persist()
        return item
    }

    func update(id: UUID, name: String, request: PlexRequest? = nil) {
        guard let index = saved.firstIndex(where: { $0.id == id }) else { return }
        saved[index].name = name
        if let request { saved[index].request = request }
        persist()
    }

    func remove(id: UUID) {
        saved.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        AppSupportStore.save(saved, name: Self.file)
    }
}
