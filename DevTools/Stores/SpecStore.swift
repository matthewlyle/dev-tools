import Foundation
import Observation

@MainActor
@Observable
final class SpecStore {
    private(set) var catalog: SpecCatalog?
    private(set) var errorMessage: String?

    func load() async {
        guard catalog == nil else { return }
        do {
            catalog = try await Task.detached(priority: .userInitiated) {
                SpecCatalog(spec: try OpenAPISpec.loadBundled())
            }.value
        } catch {
            errorMessage = "Couldn't load the bundled API spec: \(error.localizedDescription)"
        }
    }

    func operation(matching path: String) -> SpecOperation? {
        catalog?.match(path: path)
    }
}
