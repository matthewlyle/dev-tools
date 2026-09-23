import SwiftUI

/// The content well's backdrop. On macOS it's behind-window vibrancy — the
/// same desktop blur the sidebar and toolbar use, extended to the content
/// area (as Safari's start page does), toggleable in Settings. iOS has no
/// desktop behind the window, so it's the system background under a faint,
/// static wash of the accent from the top, with faint rings spreading out
/// from behind the server title, as a signal from the server every screen
/// is scoped to. Both are gone by mid-screen; they give the glass bars
/// something to refract. Increase Contrast drops both.
struct WellBackground: View {
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
                        LinearGradient(
                            colors: [.accentColor.opacity(colorScheme == .dark ? 0.16 : 0.08), .clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0.5, y: 0.55)
                        )
                        SignalRings()
                            .foregroundStyle(Color.accentColor.opacity(colorScheme == .dark ? 0.3 : 0.2))
                            .mask(RadialFromTitle())
                    }
                }
            }
            .ignoresSafeArea()
        #endif
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
    private static let spacing: CGFloat = 28
    private static let lineWidth: CGFloat = 0.75

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
