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
    @Environment(\.isCompactWidth) private var compact
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
                    LinearGradient(
                        colors: [.accentColor.opacity(colorScheme == .dark ? 0.16 : 0.08), .clear],
                        startPoint: .top,
                        endPoint: UnitPoint(x: 0.5, y: 0.55)
                    )
                }
            }
        .overlay {
            if contrast != .increased {
                GeometryReader { proxy in
                    let origin = RingOrigin(frame: proxy.frame(in: .global), compact: compact)
                    SignalRings(center: origin.center)
                        .foregroundStyle(Color.accentColor.opacity(colorScheme == .dark ? 0.2 : 0.13))
                        .modifier(ListeningPulse(active: state?.showsRings == true && !reduceMotion, anchor: origin.anchor))
                        // They swell out from the title as the connection
                        // comes up and draw back into it as it drops, under
                        // the fixed fade; the scroll fade follows the finger.
                        .scaleEffect(state?.showsRings == true || reduceMotion ? 1 : 0.9, anchor: origin.anchor)
                        .mask(RadialGradient(colors: [.white, .white.opacity(0.35), .clear], center: origin.anchor, startRadius: 0, endRadius: origin.radius))
                        .opacity(ringOpacity)
                        .animation(state?.showsRings == true ? .smooth(duration: 1.1) : .smooth(duration: 0.5), value: state?.showsRings)
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
/// Where the rings spread from: the server title. A compact width centres
/// it over its one screen. A regular-width iPad sets it at the leading end
/// of the one bar over both panes, after the sidebar button, and each pane's
/// well draws its share of the same rings in window coordinates, so they run
/// on across the seam.
private struct RingOrigin {
    /// The title's centre on a regular-width iPad, from the window's leading
    /// edge: the sidebar button, then a typical server name.
    private static let regularTitleX: CGFloat = 120

    let center: CGPoint
    let anchor: UnitPoint
    let radius: CGFloat

    init(frame: CGRect, compact: Bool) {
        let width = max(frame.width, 1)
        if compact {
            center = CGPoint(x: width / 2, y: 0)
            radius = min(width * 0.85, frame.height * 0.5)
        } else {
            // Every pane is the window's height, so a height-based radius
            // fades them alike.
            center = CGPoint(x: Self.regularTitleX - frame.minX, y: 0)
            radius = frame.height * 0.5
        }
        anchor = UnitPoint(x: center.x / width, y: 0)
    }
}

/// While the stream is live the rings breathe: a slow swell outward from the
/// title and back, dimming as they go, so Activity reads as listening. Under
/// the fixed mask, so they drift into the fade rather than past it.
private struct ListeningPulse: ViewModifier {
    let active: Bool
    let anchor: UnitPoint

    func body(content: Content) -> some View {
        // One phase rests rather than dropping the modifier, which would
        // rebuild the rings mid-fade.
        content.phaseAnimator(active ? [false, true] : [false]) { view, swelled in
            view
                .opacity(swelled ? 0.55 : 1)
                .scaleEffect(swelled ? 1.03 : 1, anchor: anchor)
        } animation: { _ in
            .easeInOut(duration: 2.4)
        }
    }
}
#endif

/// What a screen's content asks of its well: the signal rings, and how far
/// they've faded as that content scrolled from its top.
@MainActor
@Observable
final class WellState {
    nonisolated static let fadeDistance: CGFloat = 120

    var showsRings = false {
        didSet { parent?.showsRings = showsRings }
    }
    var ringFade: Double = 0 {
        didSet { parent?.ringFade = ringFade }
    }

    /// The well behind this one, where it doesn't cover it: a regular-width
    /// iPad's detail pane well sits in the one spanning both panes, which
    /// draws the rings over the list pane.
    @ObservationIgnored weak var parent: WellState?

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
    @Environment(\.well) private var enclosing
    @Environment(\.isCompactWidth) private var compact

    func body(content: Content) -> some View {
        content
            .environment(\.well, state)
            .background { WellBackground(state: state) }
            // A compact screen's inner well covers the outer one entirely.
            .onChange(of: compact, initial: true) { _, compact in
                state.parent = compact ? nil : enclosing
            }
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

    /// Fades the rings as this scroll view leaves its top.
    func fadesSignalRings() -> some View {
        modifier(SignalRingsFade())
    }
}

#if os(iOS)
/// Concentric circles around `center`, drawn once per size.
private struct SignalRings: View {
    let center: CGPoint

    private static let spacing: CGFloat = 32
    private static let lineWidth: CGFloat = 0.6

    var body: some View {
        Canvas { context, size in
            let farthest = hypot(max(center.x, size.width - center.x), size.height)
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
