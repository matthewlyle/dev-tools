import AppKit
import SwiftUI

enum Typeface {
    static let family = "CommitMono"

    static let isAvailable: Bool = {
        for url in Bundle.main.urls(forResourcesWithExtension: "otf", subdirectory: nil) ?? [] {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        return NSFont(name: "\(family)-Regular", size: 12) != nil
    }()

    static func code(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let face = weight.rawValue >= NSFont.Weight.semibold.rawValue ? "\(family)-Bold" : "\(family)-Regular"
        if isAvailable, let font = NSFont(name: face, size: size) { return font }
        return .monospacedSystemFont(ofSize: size, weight: weight)
    }
}

extension Font {
    static func code(_ style: Font.TextStyle = .body, weight: Font.Weight = .regular) -> Font {
        code(size: NSFont.preferredFont(forTextStyle: style.nsTextStyle).pointSize, weight: weight)
    }

    static func code(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        guard Typeface.isAvailable else { return .system(size: size, weight: weight, design: .monospaced) }
        return .custom(Typeface.family, fixedSize: size).weight(weight)
    }
}

private extension Font.TextStyle {
    var nsTextStyle: NSFont.TextStyle {
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
