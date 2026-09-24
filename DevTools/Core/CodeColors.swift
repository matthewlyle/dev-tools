import Foundation

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
}
