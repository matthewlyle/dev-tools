import SwiftUI

#if os(macOS)
import AppKit

typealias PlatformImage = NSImage
typealias PlatformFont = NSFont
typealias PlatformColor = NSColor
#else
import UIKit

typealias PlatformImage = UIImage
typealias PlatformFont = UIFont
typealias PlatformColor = UIColor
#endif

extension Image {
    init(platformImage: PlatformImage) {
        #if os(macOS)
        self.init(nsImage: platformImage)
        #else
        self.init(uiImage: platformImage)
        #endif
    }
}

extension PlatformColor {
    static var codeLabel: PlatformColor {
        #if os(macOS)
        .labelColor
        #else
        .label
        #endif
    }
    static var codeSecondaryLabel: PlatformColor {
        #if os(macOS)
        .secondaryLabelColor
        #else
        .secondaryLabel
        #endif
    }
    static var codeTertiaryLabel: PlatformColor {
        #if os(macOS)
        .tertiaryLabelColor
        #else
        .tertiaryLabel
        #endif
    }
    static var codeQuaternaryLabel: PlatformColor {
        #if os(macOS)
        .quaternaryLabelColor
        #else
        .quaternaryLabel
        #endif
    }

    /// On iOS the code draws straight over the well, whose wash otherwise
    /// stops at the text view's edge and leaves the body screen black against
    /// the lists around it. The well is the system background under a faint
    /// wash, so the code hues' contrast holds.
    static var codeBackground: PlatformColor {
        #if os(macOS)
        .textBackgroundColor
        #else
        .clear
        #endif
    }
    static var recessedBackground: PlatformColor {
        #if os(macOS)
        .underPageBackgroundColor
        #else
        .systemGroupedBackground
        #endif
    }

    static let codeTeal = raisedInLight(.systemTeal)
    static let codeGreen = raisedInLight(.systemGreen)
    static let codePurple = raisedInLight(.systemPurple)
    static let codeOrange = raisedInLight(.systemOrange)
    static let codeBlue = raisedInLight(.systemBlue)

    /// The system hue as-is in dark appearances, and its Increase Contrast
    /// variant in light ones: the code surface is white, where the standard
    /// hues fall under 4.5:1.
    private static func raisedInLight(_ hue: PlatformColor) -> PlatformColor {
        #if os(macOS)
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let resolving = isDark ? appearance : (highContrastAqua ?? appearance)
            var resolved = hue
            resolving.performAsCurrentDrawingAppearance { resolved = hue.usingType(.componentBased) ?? hue }
            return resolved
        }
        #else
        UIColor { traits in
            guard traits.userInterfaceStyle != .dark else { return hue.resolvedColor(with: traits) }
            return hue.resolvedColor(with: traits.modifyingTraits { $0.accessibilityContrast = .high })
        }
        #endif
    }

    #if os(macOS)
    /// `NSAppearance(named: .accessibilityHighContrastAqua)` silently returns
    /// plain Aqua; the high-contrast light appearance only loads by its
    /// catalog name from the system appearance bundle.
    private nonisolated(unsafe) static let highContrastAqua = NSAppearance(
        appearanceNamed: NSAppearance.Name("AquaAX"),
        bundle: Bundle(path: "/System/Library/CoreServices/SystemAppearance.bundle")
    )
    #endif
}

enum Clipboard {
    static func copy(_ string: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #else
        UIPasteboard.general.string = string
        #endif
    }

    static func copy(_ image: PlatformImage) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        #else
        UIPasteboard.general.image = image
        #endif
    }
}

extension Font.TextStyle {
    /// The code face sets larger on iPad than on the Mac at the same style,
    /// so list rows step down there to sit level with their neighbours.
    static var codeListRow: Font.TextStyle {
        #if os(macOS)
        .callout
        #else
        .subheadline
        #endif
    }

    /// The same step for a detail's name/value rows (response headers):
    /// iOS's body size sets the code face far larger than the Mac's.
    static var codeDetailRow: Font.TextStyle {
        #if os(macOS)
        .body
        #else
        .subheadline
        #endif
    }
}

extension EnvironmentValues {
    /// A horizontally compact layout: an iPhone, or an iPad in Slide Over or
    /// a narrow split. The Mac has no size classes and is never compact.
    var isCompactWidth: Bool {
        #if os(macOS)
        false
        #else
        horizontalSizeClass == .compact
        #endif
    }
}

extension View {
    /// Closes the Mac window hosting this view when `condition` turns true;
    /// already true when it appears doesn't count. SwiftUI's `dismiss` can't
    /// close the `Settings` scene's window. On iOS it does nothing: there a
    /// view lives in a sheet that its presenter tears down.
    func platformClosesWindow(when condition: Bool) -> some View {
        #if os(macOS)
        background(WindowCloser(condition: condition))
        #else
        self
        #endif
    }
}

#if os(macOS)
private struct WindowCloser: NSViewRepresentable {
    let condition: Bool

    final class Coordinator {
        var wasTrue: Bool
        init(_ wasTrue: Bool) { self.wasTrue = wasTrue }
    }

    func makeCoordinator() -> Coordinator { Coordinator(condition) }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        defer { context.coordinator.wasTrue = condition }
        guard condition, !context.coordinator.wasTrue else { return }
        Task { @MainActor in view.window?.close() }
    }
}
#endif
