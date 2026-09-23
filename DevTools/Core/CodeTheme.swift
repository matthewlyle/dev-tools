import Foundation

/// The code view's colours, an app-wide setting. `system` is the app's own
/// palette of system hues. The named themes are published editor palettes,
/// each with a light and a dark variant; any colour that fell under 4.5:1 on
/// its theme's background was moved to the nearest shade of the same hue that
/// clears it, so a theme is legible first and faithful second.
enum CodeTheme: String, CaseIterable, Identifiable, Sendable {
    case system
    case xcode
    case github
    case atomOne

    static let storageKey = "codeTheme"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .xcode: "Xcode"
        case .github: "GitHub"
        case .atomOne: "Atom One"
        }
    }

    var palettes: (light: CodePalette, dark: CodePalette)? {
        switch self {
        case .system: nil
        case .xcode: (.xcodeLight, .xcodeDark)
        case .github: (.githubLight, .githubDark)
        case .atomOne: (.atomOneLight, .atomOneDark)
        }
    }

    var colors: CodeColors {
        switch self {
        case .system: .system
        case .xcode: .xcode
        case .github: .github
        case .atomOne: .atomOne
        }
    }
}

/// One appearance of a theme, as `0xRRGGBB`.
struct CodePalette: Sendable {
    let background: UInt32
    let text: UInt32
    let key: UInt32
    let string: UInt32
    let number: UInt32
    let literal: UInt32
    let null: UInt32
    let punctuation: UInt32
    let tag: UInt32
    let attributeName: UInt32
    let attributeValue: UInt32
    let comment: UInt32

    /// Every colour drawn over `background`.
    var foregrounds: [UInt32] {
        [text, key, string, number, literal, null, punctuation, tag, attributeName, attributeValue, comment]
    }

    static let xcodeLight = CodePalette(
        background: 0xFFFFFF, text: 0x262626, key: 0x326D74, string: 0xC41A16, number: 0x1C00CF,
        literal: 0x9B2393, null: 0x5D6C79, punctuation: 0x6C6C70, tag: 0x0B4F79,
        attributeName: 0x326D74, attributeValue: 0xC41A16, comment: 0x5D6C79
    )
    static let xcodeDark = CodePalette(
        background: 0x1F1F24, text: 0xDFDFE0, key: 0x67B7A4, string: 0xFC6A5D, number: 0xD0BF69,
        literal: 0xFC5FA3, null: 0x7D8A96, punctuation: 0xA0A0A8, tag: 0x5DD8FF,
        attributeName: 0x67B7A4, attributeValue: 0xFC6A5D, comment: 0x7D8A96
    )
    static let githubLight = CodePalette(
        background: 0xFFFFFF, text: 0x1F2328, key: 0x116329, string: 0x0A3069, number: 0x0550AE,
        literal: 0x0550AE, null: 0x59636E, punctuation: 0x59636E, tag: 0x116329,
        attributeName: 0x6639BA, attributeValue: 0x0A3069, comment: 0x59636E
    )
    static let githubDark = CodePalette(
        background: 0x0D1117, text: 0xE6EDF3, key: 0x7EE787, string: 0xA5D6FF, number: 0x79C0FF,
        literal: 0x79C0FF, null: 0x8B949E, punctuation: 0x8B949E, tag: 0x7EE787,
        attributeName: 0xD2A8FF, attributeValue: 0xA5D6FF, comment: 0x8B949E
    )
    static let atomOneLight = CodePalette(
        background: 0xFAFAFA, text: 0x383A42, key: 0xD72F20, string: 0x3F7F3E, number: 0x986801,
        literal: 0x0179AD, null: 0x707179, punctuation: 0x696C77, tag: 0xD72F20,
        attributeName: 0x986801, attributeValue: 0x3F7F3E, comment: 0x707179
    )
    static let atomOneDark = CodePalette(
        background: 0x282C34, text: 0xABB2BF, key: 0xE2747D, string: 0x98C379, number: 0xD19A66,
        literal: 0x56B6C2, null: 0x91959E, punctuation: 0xABB2BF, tag: 0xE2747D,
        attributeName: 0xD19A66, attributeValue: 0x98C379, comment: 0x91959E
    )
}

/// A theme resolved to platform colours, built once per theme because the
/// renderer asks for a colour per token.
struct CodeColors: Sendable {
    let background: PlatformColor
    let text: PlatformColor
    private let key: PlatformColor
    private let string: PlatformColor
    private let number: PlatformColor
    private let literal: PlatformColor
    private let null: PlatformColor
    private let punctuation: PlatformColor
    private let tag: PlatformColor
    private let attributeName: PlatformColor
    private let attributeValue: PlatformColor
    private let comment: PlatformColor

    func color(for kind: TokenKind) -> PlatformColor {
        switch kind {
        case .key: key
        case .string: string
        case .number: number
        case .literal: literal
        case .null: null
        case .punctuation: punctuation
        case .tagName: tag
        case .attributeName: attributeName
        case .attributeValue: attributeValue
        case .comment, .processingInstruction: comment
        }
    }

    static let system = CodeColors(
        background: .codeBackground, text: .codeLabel, key: .codeTeal, string: .codeGreen, number: .codePurple,
        literal: .codeOrange, null: .codeSecondaryLabel, punctuation: .codeSecondaryLabel, tag: .codeBlue,
        attributeName: .codeTeal, attributeValue: .codeGreen, comment: .codeTertiaryLabel
    )
    static let xcode = CodeColors(light: .xcodeLight, dark: .xcodeDark)
    static let github = CodeColors(light: .githubLight, dark: .githubDark)
    static let atomOne = CodeColors(light: .atomOneLight, dark: .atomOneDark)

    private init(
        background: PlatformColor, text: PlatformColor, key: PlatformColor, string: PlatformColor,
        number: PlatformColor, literal: PlatformColor, null: PlatformColor, punctuation: PlatformColor,
        tag: PlatformColor, attributeName: PlatformColor, attributeValue: PlatformColor, comment: PlatformColor
    ) {
        self.background = background
        self.text = text
        self.key = key
        self.string = string
        self.number = number
        self.literal = literal
        self.null = null
        self.punctuation = punctuation
        self.tag = tag
        self.attributeName = attributeName
        self.attributeValue = attributeValue
        self.comment = comment
    }

    private init(light: CodePalette, dark: CodePalette) {
        func pair(_ value: KeyPath<CodePalette, UInt32>) -> PlatformColor {
            .appearance(light: light[keyPath: value], dark: dark[keyPath: value])
        }
        self.init(
            background: pair(\.background), text: pair(\.text), key: pair(\.key), string: pair(\.string),
            number: pair(\.number), literal: pair(\.literal), null: pair(\.null), punctuation: pair(\.punctuation),
            tag: pair(\.tag), attributeName: pair(\.attributeName), attributeValue: pair(\.attributeValue),
            comment: pair(\.comment)
        )
    }
}
