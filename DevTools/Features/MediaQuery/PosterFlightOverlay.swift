import SwiftUI

/// Window-wide layer that flies a selected poster from its grid cell to the
/// inspector hero, then crossfades into the hero. Both ends are the same size,
/// so the flight is a pure move, and the pixels are the grid cell's cached
/// decode. Never launched under Reduce Motion.
struct PosterFlightOverlay: View {
    @Environment(PosterFlightStore.self) private var flights

    var body: some View {
        ZStack {
            if let flight = flights.flight {
                FlyingPoster(flight: flight)
                    .id(flight.id)
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private struct FlyingPoster: View {
        let flight: PosterFlightStore.Flight

        @Environment(PosterFlightStore.self) private var flights
        @Environment(ImageStore.self) private var images
        @State private var departed = false

        var body: some View {
            GeometryReader { proxy in
                let bounds = proxy.frame(in: .global)
                let target = departed ? (flights.destination ?? flight.source) : flight.source
                let rect = target.offsetBy(dx: -bounds.minX, dy: -bounds.minY)

                art
                    .frame(width: flight.size.width, height: flight.size.height)
                    .clipShape(.rect(cornerRadius: 8))
                    .position(x: rect.midX, y: rect.midY)
                    // The hero moves while the inspector column slides in; the
                    // spring retargets instead of jumping.
                    .animation(.smooth, value: rect)
            }
            .ignoresSafeArea()
            // Departs only once the hero has a frame to aim for: the inspector
            // lays out a pass after the selection that opens it.
            .onChange(of: flights.destination != nil, initial: true) { _, known in
                guard known, !departed else { return }
                withAnimation(.smooth) {
                    departed = true
                } completion: {
                    withAnimation(.smooth(duration: 0.2)) { flights.land(flight.id) }
                }
            }
        }

        @ViewBuilder
        private var art: some View {
            let pixels = (Int(flight.size.width * 2), Int(flight.size.height * 2))
            if let image = images.cachedImage(for: flight.thumb, server: flight.server, width: pixels.0, height: pixels.1) {
                Image(platformImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(.quaternary)
            }
        }
    }
}
