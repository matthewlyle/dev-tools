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
    static var codeBackground: PlatformColor {
        #if os(macOS)
        .textBackgroundColor
        #else
        .systemBackground
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

    /// A fixed sRGB colour per appearance, from `0xRRGGBB` values.
    static func appearance(light: UInt32, dark: UInt32) -> PlatformColor {
        let light = srgb(light), dark = srgb(dark)
        #if os(macOS)
        return NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light }
        #else
        return UIColor { $0.userInterfaceStyle == .dark ? dark : light }
        #endif
    }

    private static func srgb(_ hex: UInt32) -> PlatformColor {
        let r = CGFloat((hex >> 16) & 0xFF) / 255, g = CGFloat((hex >> 8) & 0xFF) / 255, b = CGFloat(hex & 0xFF) / 255
        #if os(macOS)
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
        #else
        return UIColor(red: r, green: g, blue: b, alpha: 1)
        #endif
    }

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
}
