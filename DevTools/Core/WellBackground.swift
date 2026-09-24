import SwiftUI

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
    private var ringOpacity: Double {
        guard let state, state.showsRings else { return 0 }
        return 1 - state.ringFade
    }
    #endif
}

#if os(iOS)
private struct RingOrigin {
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
            // Panes draw shares of one set of rings in window coordinates, all
            // at the window's height, so a height-based radius fades them alike.
            center = CGPoint(x: Self.regularTitleX - frame.minX, y: 0)
            radius = frame.height * 0.5
        }
        anchor = UnitPoint(x: center.x / width, y: 0)
    }
}

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

    @ObservationIgnored weak var parent: WellState?

    /// Quantized to twentieths so a scroll updates the well a handful of
    /// times, not every frame.
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
            .onChange(of: compact, initial: true) { _, compact in
                state.parent = compact ? nil : enclosing
            }
    }
}

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
    func wellBackground() -> some View {
        modifier(WellBackgroundModifier())
    }

    func signalRings(visible: Bool) -> some View {
        modifier(WellRequest(flag: \.showsRings, visible: visible))
    }

    func fadesSignalRings() -> some View {
        modifier(SignalRingsFade())
    }
}

#if os(iOS)
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
