import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Commit Mono, declared to the system in `Info.plist` (`UIAppFonts` /
/// `ATSApplicationFontsPath`). Two faces are bundled, so weight resolves to
/// a face here rather than letting each platform's matcher pick.
enum Typeface {
    static let family = "CommitMono"

    static let isAvailable = PlatformFont(name: face(bold: false), size: 12) != nil

    static func face(bold: Bool) -> String {
        bold ? "\(family)-Bold" : "\(family)-Regular"
    }

    static func code(size: CGFloat, weight: PlatformFont.Weight = .regular) -> PlatformFont {
        let bold = weight.rawValue >= PlatformFont.Weight.semibold.rawValue
        if isAvailable, let font = PlatformFont(name: face(bold: bold), size: size) { return font }
        return .monospacedSystemFont(ofSize: size, weight: weight)
    }
}

extension Font {
    static func code(_ style: Font.TextStyle = .body, weight: Font.Weight = .regular) -> Font {
        code(size: PlatformFont.preferredFont(forTextStyle: style.platformTextStyle).pointSize, weight: weight)
    }

    static func code(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        guard Typeface.isAvailable else { return .system(size: size, weight: weight, design: .monospaced) }
        let bold = [.semibold, .bold, .heavy, .black].contains(weight)
        return .custom(Typeface.face(bold: bold), fixedSize: size)
    }
}

private extension Font.TextStyle {
    var platformTextStyle: PlatformFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .body: .body
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        @unknown default: .body
        }
    }
}
