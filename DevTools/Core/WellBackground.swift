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
        Color(uiColor: .systemBackground)
            .overlay {
                if contrast != .increased {
                    ZStack {
                        TopWash(strength: colorScheme == .dark ? 1 : 0.5)
                        SignalRings()
                            .foregroundStyle(Color.accentColor.opacity(colorScheme == .dark ? 0.2 : 0.13))
                            .modifier(ListeningPulse(active: state?.showsRings == true && !reduceMotion))
                            .mask(RadialFromTitle())
                            .opacity(ringOpacity)
                            // Rise with the connection, leave quickly when it
                            // drops; the scroll fade follows the finger.
                            .animation(state?.showsRings == true ? .smooth(duration: 0.6) : .easeOut(duration: 0.2), value: state?.showsRings)
                    }
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
        if active {
            content.phaseAnimator([false, true]) { view, swelled in
                view
                    .opacity(swelled ? 0.55 : 1)
                    .scaleEffect(swelled ? 1.03 : 1, anchor: .top)
            } animation: { _ in
                .easeInOut(duration: 2.4)
            }
        } else {
            content
        }
    }
}
#endif

#if os(iOS)
/// Three hues along the top edge blending down to nothing: indigo at the
/// leading corner, the accent brightest just under the title, teal at the
/// trailing corner. The middle row bows down under the title so the glow
/// gathers there rather than lying in a flat band.
private struct TopWash: View {
    let strength: Double

    var body: some View {
        MeshGradient(
            width: 3,
            height: 4,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.22], [0.5, 0.3], [1, 0.22],
                [0, 0.55], [0.5, 0.58], [1, 0.55],
                [0, 1], [0.5, 1], [1, 1],
            ],
            colors: [
                .indigo.opacity(0.16 * strength), .accentColor.opacity(0.2 * strength), .teal.opacity(0.14 * strength),
                .indigo.opacity(0.05 * strength), .accentColor.opacity(0.1 * strength), .teal.opacity(0.04 * strength),
                .clear, .clear, .clear,
                .clear, .clear, .clear,
            ]
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
