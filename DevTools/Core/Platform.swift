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

/// The system label/background colours the highlighted response text draws
/// with, under the name each platform uses.
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

@MainActor
enum SystemBrowser {
    static func open(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }
}

extension View {
    /// `navigationSubtitle` exists only on macOS; a no-op elsewhere.
    @ViewBuilder
    func platformNavigationSubtitle(_ subtitle: String) -> some View {
        #if os(macOS)
        navigationSubtitle(subtitle)
        #else
        self
        #endif
    }

    /// A checkbox on macOS; the platform-standard switch on iPadOS, which has
    /// no checkbox style.
    @ViewBuilder
    func platformCheckboxToggleStyle() -> some View {
        #if os(macOS)
        toggleStyle(.checkbox)
        #else
        toggleStyle(.switch)
        #endif
    }
}

extension SearchFieldPlacement {
    /// `.toolbar` is macOS-only; iPadOS resolves the search field automatically
    /// within the column's navigation bar.
    static var platformToolbar: SearchFieldPlacement {
        #if os(macOS)
        .toolbar
        #else
        .automatic
        #endif
    }
}
