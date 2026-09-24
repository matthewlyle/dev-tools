import Foundation
import Observation

struct LightboxItem: Identifiable, Hashable, Sendable {
    let url: String
    let title: String

    var id: String { url }
}

@MainActor
@Observable
final class LightboxStore {
    struct Presentation {
        let item: LightboxItem
        let server: ConnectedServer
        let sourceFrame: CGRect
        /// Must match the thumbnail's fetch size so the lightbox's first frame
        /// is a cache hit on the same pixels.
        let previewPixelSize: CGSize
    }

    private(set) var presentation: Presentation?

    func open(_ item: LightboxItem, on server: ConnectedServer, from frame: CGRect, preview: CGSize) {
        presentation = Presentation(item: item, server: server, sourceFrame: frame, previewPixelSize: preview)
    }

    func close() {
        presentation = nil
    }
}
