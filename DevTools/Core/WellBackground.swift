import SwiftUI

/// The content well's backdrop. On macOS it's behind-window vibrancy — the
/// same desktop blur the sidebar and toolbar use, extended to the content
/// area (as Safari's start page does), toggleable in Settings. iOS has no
/// desktop behind the window, so it's the system background under a faint,
/// static mesh of colour across the top — indigo, the accent strongest
/// behind the server title, teal — with faint rings spreading out from the
/// title, as a signal from the server every screen is scoped to. Both are
/// gone by mid-screen; they give the glass bars something to refract.
/// Increase Contrast drops both.
struct WellBackground: View {
    var scroll: WellScroll? = nil

    @AppStorage("translucentBackground") private var translucent = true
    #if os(iOS)
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
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
                        // The rings belong to the top of the screen; once its
                        // content scrolls under the bar they give way to it.
                        SignalRings()
                            .foregroundStyle(Color.accentColor.opacity(colorScheme == .dark ? 0.2 : 0.13))
                            .mask(RadialFromTitle())
                            .opacity(1 - (scroll?.fade ?? 0))
                    }
                }
            }
            .ignoresSafeArea()
        #endif
    }
}

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

/// How far a screen's content has scrolled from its top, as the share of the
/// fade distance its rings have faded, from every scroll view on the screen
/// that reports. The furthest-scrolled one wins, so an iPad's list or detail
/// scrolling under the bar fades them either way.
@MainActor
@Observable
final class WellScroll {
    nonisolated static let fadeDistance: CGFloat = 120

    private var progress: [UUID: Double] = [:]

    var fade: Double { progress.values.max() ?? 0 }

    func set(_ value: Double, for reporter: UUID) {
        guard progress[reporter] != value else { return }
        progress[reporter] = value
    }

    func remove(_ reporter: UUID) {
        progress[reporter] = nil
    }

    /// Offset from the top as a fade share, in twentieths, so a scroll
    /// updates the well a handful of times, not every frame.
    nonisolated static func share(scrolled offset: CGFloat) -> Double {
        (Double(min(max(offset / fadeDistance, 0), 1)) * 20).rounded() / 20
    }
}

extension EnvironmentValues {
    @Entry var wellScroll: WellScroll? = nil
}

private struct WellBackgroundModifier: ViewModifier {
    @State private var scroll = WellScroll()

    func body(content: Content) -> some View {
        content
            .environment(\.wellScroll, scroll)
            .background { WellBackground(scroll: scroll) }
    }
}

private struct WellScrollReporter: ViewModifier {
    @Environment(\.wellScroll) private var scroll
    @Environment(\.sectionIsActive) private var isActive
    @State private var id = UUID()
    @State private var share: Double = 0

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .onScrollGeometryChange(for: Double.self) { geometry in
                WellScroll.share(scrolled: geometry.contentOffset.y + geometry.contentInsets.top)
            } action: { _, value in
                share = value
                report()
            }
            // A hidden resident section keeps its scroll position; it mustn't
            // hold the rings faded on the one that's showing.
            .onChange(of: isActive) { _, _ in report() }
            .onDisappear { scroll?.remove(id) }
        #else
        content
        #endif
    }

    private func report() {
        scroll?.set(isActive ? share : 0, for: id)
    }
}

extension View {
    /// The screen's well, whose rings fade as scroll views inside it that
    /// `reportsWellScroll()` move off their top.
    func wellBackground() -> some View {
        modifier(WellBackgroundModifier())
    }

    func reportsWellScroll() -> some View {
        modifier(WellScrollReporter())
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
