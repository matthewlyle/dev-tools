import Foundation
import Observation

/// One entry in the lightbox: a server image path and what Plex calls it.
struct LightboxItem: Identifiable, Hashable, Sendable {
    let url: String
    let title: String

    var id: String { url }
}

/// What the lightbox is showing and where it came from, so the root overlay
/// can grow the image out of its thumbnail and shrink it back.
@MainActor
@Observable
final class LightboxStore {
    struct Presentation {
        let item: LightboxItem
        let server: ConnectedServer
        /// The thumbnail's frame in window coordinates.
        let sourceFrame: CGRect
        /// The pixel size the thumbnail was fetched at, so the lightbox's first
        /// frame is a cache hit on the same pixels.
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
