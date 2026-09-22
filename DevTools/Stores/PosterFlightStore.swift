import Foundation
import Observation

/// A poster travelling from its grid cell to the Media inspector's hero. The
/// two ends sit in different split columns, and `matchedGeometryEffect` pins a
/// non-source view onto its source for as long as both are on screen, so the
/// flight is drawn in the root overlay between their window frames, like the
/// lightbox.
@MainActor
@Observable
final class PosterFlightStore {
    struct Flight: Identifiable {
        let id = UUID()
        let itemID: Int
        let thumb: String
        let server: ConnectedServer
        let size: CGSize
        /// The grid cell's art frame in window coordinates.
        let source: CGRect
    }

    private(set) var flight: Flight?
    /// The inspector hero's frame in window coordinates while it's on screen.
    var destination: CGRect?

    func launch(_ flight: Flight) {
        self.flight = flight
    }

    /// Ends `id`'s flight, or whichever is in the air when `id` is nil. A
    /// finished flight never ends the one that replaced it.
    func land(_ id: UUID? = nil) {
        guard let flight, id == nil || flight.id == id else { return }
        self.flight = nil
    }
}
