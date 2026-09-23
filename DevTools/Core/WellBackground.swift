import SwiftUI

/// The content well's backdrop. On macOS it's behind-window vibrancy — the
/// same desktop blur the sidebar and toolbar use, extended to the content
/// area (as Safari's start page does), toggleable in Settings. iOS has no
/// desktop behind the window, so it's the system background under a faint,
/// static wash of the accent from the top, gone by mid-screen, which gives
/// the glass bars something to refract. While Activity is live, faint rings
/// spread from the title as the server's signal. Increase Contrast drops
/// both.
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
        // Drawn as one opaque layer in extended linear colour: an alpha
        // gradient this faint, rasterised into its own 8-bit layer before
        // compositing, has only a few dozen levels to fade through, and the
        // grain can only dither what's left if it's mixed in at float depth.
        ZStack {
            Color(uiColor: .systemBackground)
            if contrast != .increased {
                LinearGradient(
                    colors: [.accentColor.opacity(colorScheme == .dark ? 0.16 : 0.08), .accentColor.opacity(0)],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: 0.55)
                )
                Grain()
            }
        }
        .drawingGroup(opaque: true, colorMode: .extendedLinear)
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
                // The land the rings carry over, only while there's nothing
                // on screen to sit behind: gone as the first event arrives.
                Ridgelines(hue: .accentColor, strength: colorScheme == .dark ? 1 : 0.6)
                    .opacity(state?.showsRidges == true ? 1 : 0)
                    .animation(state?.showsRidges == true ? .smooth(duration: 0.9) : .easeOut(duration: 0.25), value: state?.showsRidges)
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
/// Three layered ridgelines along the bottom, the nearest the most solid.
/// Their wavelengths are in points, not a share of the width, so a wider
/// screen shows more mountains rather than stretched ones, and the shapes
/// are fixed, so they don't change between launches.
private struct Ridgelines: View {
    let hue: Color
    let strength: Double

    private struct Layer {
        let height: CGFloat
        let opacity: Double
        let phase: CGFloat
    }

    private static let layers = [
        Layer(height: 170, opacity: 0.05, phase: 0.8),
        Layer(height: 125, opacity: 0.08, phase: 2.9),
        Layer(height: 80, opacity: 0.12, phase: 5.1),
    ]

    var body: some View {
        Canvas { context, size in
            for layer in Self.layers {
                context.fill(Self.ridge(layer, in: size), with: .color(hue.opacity(layer.opacity * strength)))
            }
        }
        .accessibilityHidden(true)
    }

    /// Main peaks, smaller ones between, and a little jaggedness, each a
    /// folded sine sharpened to a point, over a long swell so the range
    /// rises and falls.
    private static func ridge(_ layer: Layer, in size: CGSize) -> Path {
        func height(at x: CGFloat) -> CGFloat {
            func peak(_ wavelength: CGFloat, _ shift: CGFloat) -> CGFloat { pow(1 - abs(sin(x / wavelength + shift)), 2.2) }
            let swell = 0.5 + 0.5 * sin(x / 230 + layer.phase * 0.6)
            return layer.height * (0.28 + 0.5 * peak(95, layer.phase) + 0.16 * peak(41, layer.phase * 1.9) + 0.05 * peak(13, layer.phase * 3.7) + 0.18 * swell)
        }
        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height))
        var x: CGFloat = 0
        while x <= size.width + 4 {
            path.addLine(to: CGPoint(x: x, y: size.height - height(at: x)))
            x += 4
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()
        return path
    }
}
#endif

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

#endif

/// What a screen's content asks of its well: the signal rings and how far
/// they've faded as that content scrolled from its top, and the ridgelines.
@MainActor
@Observable
final class WellState {
    nonisolated static let fadeDistance: CGFloat = 120

    var showsRings = false
    var ringFade: Double = 0
    var showsRidges = false

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

/// Holds one of the well's flags while `visible`, and lets go when the
/// content asking for it leaves.
private struct WellRequest: ViewModifier {
    let flag: ReferenceWritableKeyPath<WellState, Bool>
    let visible: Bool

    @Environment(\.well) private var well

    func body(content: Content) -> some View {
        content
            .onChange(of: visible, initial: true) { _, visible in
                well?[keyPath: flag] = visible
            }
            .onDisappear { well?[keyPath: flag] = false }
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
        modifier(WellRequest(flag: \.showsRings, visible: visible))
    }

    /// Raises the screen well's ridgelines while `visible`.
    func ridgelines(visible: Bool) -> some View {
        modifier(WellRequest(flag: \.showsRidges, visible: visible))
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
