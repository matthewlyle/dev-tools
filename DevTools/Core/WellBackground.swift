import SwiftUI

/// The content well's backdrop. On macOS it's behind-window vibrancy — the
/// same desktop blur the sidebar and toolbar use, extended to the content
/// area (as Safari's start page does), toggleable in Settings. iOS has no
/// desktop behind the window, so it's the system background under a faint,
/// static mesh of colour across the top — indigo, the accent strongest
/// behind the server title, teal — gone by mid-screen, which gives the glass
/// bars something to refract. While Activity is live, faint rings spread
/// from the title as the server's signal. Increase Contrast drops both.
struct WellBackground: View {
    var state: WellState? = nil

    @AppStorage("translucentBackground") private var translucent = true
    #if os(iOS)
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #endif

    var body: some View {
        #if os(macOS)
        if translucent {
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
        } else {
            Color(PlatformColor.recessedBackground)
                .ignoresSafeArea()
        }
        #else
        ZStack {
            Color(uiColor: .systemBackground)
            if contrast != .increased {
                TopWash(strength: colorScheme == .dark ? 1 : 0.5)
                Grain()
            }
        }
        .overlay {
            if contrast != .increased {
                SignalRings()
                    .foregroundStyle(Color.accentColor.opacity(colorScheme == .dark ? 0.2 : 0.13))
                    .modifier(ListeningPulse(active: state?.showsRings == true && !reduceMotion))
                    // They swell out from the title as the connection comes
                    // up and draw back into it as it drops, under the fixed
                    // fade; the scroll fade follows the finger.
                    .scaleEffect(state?.showsRings == true || reduceMotion ? 1 : 0.9, anchor: .top)
                    .mask(RadialFromTitle())
                    .opacity(ringOpacity)
                    .animation(state?.showsRings == true ? .smooth(duration: 1.1) : .smooth(duration: 0.5), value: state?.showsRings)
            }
        }
        .ignoresSafeArea()
        #endif
    }

    #if os(iOS)
    /// They belong to the top of the screen; once its content scrolls under
    /// the bar they give way to it.
    private var ringOpacity: Double {
        guard let state, state.showsRings else { return 0 }
        return 1 - state.ringFade
    }
    #endif
}

#if os(iOS)
/// While the stream is live the rings breathe: a slow swell outward from the
/// title and back, dimming as they go, so Activity reads as listening. Under
/// the fixed mask, so they drift into the fade rather than past it.
private struct ListeningPulse: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        // One phase rests rather than dropping the modifier, which would
        // rebuild the rings mid-fade.
        content.phaseAnimator(active ? [false, true] : [false]) { view, swelled in
            view
                .opacity(swelled ? 0.55 : 1)
                .scaleEffect(swelled ? 1.03 : 1, anchor: .top)
        } animation: { _ in
            .easeInOut(duration: 2.4)
        }
    }
}
#endif

#if os(iOS)
/// A faint gradient over a dark background spans only a few 8-bit steps,
/// which show as bands; grain of about a step per pixel, over the washed
/// area only, breaks their edges up. One random tile, made once and tiled.
private struct Grain: View {
    private static let tile: CGImage? = {
        let side = 128
        var alpha = [UInt8](repeating: 0, count: side * side)
        var generator = SystemRandomNumberGenerator()
        for index in alpha.indices { alpha[index] = UInt8.random(in: 0...255, using: &generator) }
        guard let provider = CGDataProvider(data: Data(alpha) as CFData) else { return nil }
        return CGImage(
            width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: side,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }()

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        if let tile = Self.tile {
            Image(decorative: tile, scale: displayScale)
                .resizable(resizingMode: .tile)
                .opacity(0.02)
                .mask {
                    LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.62))
                }
                .accessibilityHidden(true)
        }
    }
}

/// Three hues along the top edge blending down to nothing: indigo at the
/// leading corner, the accent brightest just under the title, teal at the
/// trailing corner. The second row bows down under the title so the glow
/// gathers there. Each hue eases out over several rows to its own
/// transparent self, not to `.clear` (transparent black, which greys the
/// blend): a fade that stops at one row shows where it stops.
private struct TopWash: View {
    let strength: Double

    var body: some View {
        let indigo = Color.indigo, accent = Color.accentColor, teal = Color.teal
        let rows: [Double] = [1, 0.5, 0.2, 0.05, 0]
        return MeshGradient(
            width: 3,
            height: 5,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.16], [0.5, 0.22], [1, 0.16],
                [0, 0.34], [0.5, 0.4], [1, 0.34],
                [0, 0.58], [0.5, 0.62], [1, 0.58],
                [0, 1], [0.5, 1], [1, 1],
            ],
            colors: rows.flatMap { share in
                [indigo.opacity(0.16 * strength * share), accent.opacity(0.2 * strength * share), teal.opacity(0.14 * strength * share)]
            },
            colorSpace: .perceptual
        )
        .accessibilityHidden(true)
    }
}
#endif

/// What a screen's content asks of its well: the signal rings, and how far
/// they've faded as that content scrolled from its top.
@MainActor
@Observable
final class WellState {
    nonisolated static let fadeDistance: CGFloat = 120

    var showsRings = false
    var ringFade: Double = 0

    /// Offset from the top as a fade share, in twentieths, so a scroll
    /// updates the well a handful of times, not every frame.
    nonisolated static func share(scrolled offset: CGFloat) -> Double {
        (Double(min(max(offset / fadeDistance, 0), 1)) * 20).rounded() / 20
    }
}

extension EnvironmentValues {
    @Entry var well: WellState? = nil
}

private struct WellBackgroundModifier: ViewModifier {
    @State private var state = WellState()

    func body(content: Content) -> some View {
        content
            .environment(\.well, state)
            .background { WellBackground(state: state) }
    }
}

private struct SignalRingsRequest: ViewModifier {
    let visible: Bool

    @Environment(\.well) private var well

    func body(content: Content) -> some View {
        content
            .onChange(of: visible, initial: true) { _, visible in
                well?.showsRings = visible
            }
            .onDisappear { well?.showsRings = false }
    }
}

private struct SignalRingsFade: ViewModifier {
    @Environment(\.well) private var well

    func body(content: Content) -> some View {
        #if os(iOS)
        content.onScrollGeometryChange(for: Double.self) { geometry in
            WellState.share(scrolled: geometry.contentOffset.y + geometry.contentInsets.top)
        } action: { _, share in
            well?.ringFade = share
        }
        #else
        content
        #endif
    }
}

extension View {
    /// The screen's well, owning what its content asks of it.
    func wellBackground() -> some View {
        modifier(WellBackgroundModifier())
    }

    /// Raises the screen well's signal rings while `visible`.
    func signalRings(visible: Bool) -> some View {
        modifier(SignalRingsRequest(visible: visible))
    }

    /// Fades the rings as this scroll view leaves its top.
    func fadesSignalRings() -> some View {
        modifier(SignalRingsFade())
    }
}

#if os(iOS)
/// Opaque at the top centre, where the server title sits, clearing in a
/// circle whose radius follows the width, so a phone and an iPad spread
/// the same way.
private struct RadialFromTitle: View {
    var body: some View {
        GeometryReader { proxy in
            RadialGradient(
                colors: [.white, .white.opacity(0.35), .clear],
                center: .top,
                startRadius: 0,
                endRadius: min(proxy.size.width * 0.85, proxy.size.height * 0.5)
            )
        }
    }
}
#endif

#if os(iOS)
/// Concentric circles around the top centre, drawn once per size.
private struct SignalRings: View {
    private static let spacing: CGFloat = 32
    private static let lineWidth: CGFloat = 0.6

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: 0)
            let farthest = hypot(size.width / 2, size.height)
            var rings = Path()
            var radius = Self.spacing
            while radius < farthest {
                rings.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
                radius += Self.spacing
            }
            context.stroke(rings, with: .foreground, lineWidth: Self.lineWidth)
        }
        .accessibilityHidden(true)
    }
}
#endif

#if os(macOS)
private struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
    }
}
#endif
