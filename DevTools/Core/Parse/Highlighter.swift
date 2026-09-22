import Foundation

enum TokenKind: Sendable, Hashable {
    case key
    case string
    case number
    case literal
    case null
    case punctuation
    case tagName
    case attributeName
    case attributeValue
    case comment
    case processingInstruction
}

struct Token: Sendable, Hashable {
    let location: Int
    let length: Int
    let kind: TokenKind

    var nsRange: NSRange { NSRange(location: location, length: length) }
}

enum Highlighter {
    private static let quote: UInt16 = 0x22
    private static let backslash: UInt16 = 0x5C
    private static let colon: UInt16 = 0x3A
    private static let comma: UInt16 = 0x2C
    private static let openBrace: UInt16 = 0x7B
    private static let closeBrace: UInt16 = 0x7D
    private static let openBracket: UInt16 = 0x5B
    private static let closeBracket: UInt16 = 0x5D
    private static let lessThan: UInt16 = 0x3C
    private static let greaterThan: UInt16 = 0x3E
    private static let slash: UInt16 = 0x2F
    private static let equals: UInt16 = 0x3D
    private static let apostrophe: UInt16 = 0x27
    private static let exclamation: UInt16 = 0x21
    private static let question: UInt16 = 0x3F
    private static let hyphen: UInt16 = 0x2D

    private static func isWhitespace(_ c: UInt16) -> Bool {
        c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D
    }

    private static func isDigit(_ c: UInt16) -> Bool {
        c >= 0x30 && c <= 0x39
    }

    private static func isLetter(_ c: UInt16) -> Bool {
        (c >= 0x61 && c <= 0x7A) || (c >= 0x41 && c <= 0x5A)
    }

    static func json(_ text: String) -> [Token] {
        let u = Array(text.utf16)
        let n = u.count
        var tokens: [Token] = []
        tokens.reserveCapacity(n / 6)
        var i = 0

        while i < n {
            let c = u[i]
            if c == quote {
                let start = i
                i += 1
                while i < n, u[i] != quote {
                    i += u[i] == backslash ? 2 : 1
                }
                i = min(i + 1, n)
                var look = i
                while look < n, isWhitespace(u[look]) { look += 1 }
                let kind: TokenKind = (look < n && u[look] == colon) ? .key : .string
                tokens.append(Token(location: start, length: i - start, kind: kind))
            } else if c == hyphen || isDigit(c) {
                let start = i
                i += 1
                while i < n, isDigit(u[i]) || u[i] == 0x2E || u[i] == 0x65 || u[i] == 0x45 || u[i] == 0x2B || u[i] == hyphen {
                    i += 1
                }
                tokens.append(Token(location: start, length: i - start, kind: .number))
            } else if isLetter(c) {
                let start = i
                while i < n, isLetter(u[i]) { i += 1 }
                let isNull = i - start == 4 && u[start] == 0x6E && u[start + 1] == 0x75 && u[start + 2] == 0x6C && u[start + 3] == 0x6C
                tokens.append(Token(location: start, length: i - start, kind: isNull ? .null : .literal))
            } else if c == openBrace || c == closeBrace || c == openBracket || c == closeBracket || c == colon || c == comma {
                tokens.append(Token(location: i, length: 1, kind: .punctuation))
                i += 1
            } else {
                i += 1
            }
        }
        return tokens
    }

    static func xml(_ text: String) -> [Token] {
        let u = Array(text.utf16)
        let n = u.count
        var tokens: [Token] = []
        tokens.reserveCapacity(n / 8)
        var i = 0

        func starts(with pattern: [UInt16], at index: Int) -> Bool {
            guard index + pattern.count <= n else { return false }
            for (offset, p) in pattern.enumerated() where u[index + offset] != p { return false }
            return true
        }

        func indexOf(_ pattern: [UInt16], from index: Int) -> Int? {
            var j = index
            while j + pattern.count <= n {
                if starts(with: pattern, at: j) { return j }
                j += 1
            }
            return nil
        }

        let commentOpen = Array("<!--".utf16)
        let commentClose = Array("-->".utf16)
        let piOpen: [UInt16] = [lessThan, question]
        let piClose: [UInt16] = [question, greaterThan]
        let cdataOpen = Array("<![CDATA[".utf16)
        let cdataClose = Array("]]>".utf16)

        while i < n {
            guard u[i] == lessThan else {
                i += 1
                continue
            }

            if starts(with: commentOpen, at: i) {
                let end = indexOf(commentClose, from: i + 4).map { $0 + 3 } ?? n
                tokens.append(Token(location: i, length: end - i, kind: .comment))
                i = end
                continue
            }
            if starts(with: piOpen, at: i) {
                let end = indexOf(piClose, from: i + 2).map { $0 + 2 } ?? n
                tokens.append(Token(location: i, length: end - i, kind: .processingInstruction))
                i = end
                continue
            }
            if starts(with: cdataOpen, at: i) {
                let end = indexOf(cdataClose, from: i + 9).map { $0 + 3 } ?? n
                tokens.append(Token(location: i, length: end - i, kind: .string))
                i = end
                continue
            }
            if i + 1 < n, u[i + 1] == exclamation {
                var end = i
                while end < n, u[end] != greaterThan { end += 1 }
                end = min(end + 1, n)
                tokens.append(Token(location: i, length: end - i, kind: .processingInstruction))
                i = end
                continue
            }

            tokens.append(Token(location: i, length: 1, kind: .punctuation))
            i += 1
            if i < n, u[i] == slash {
                tokens.append(Token(location: i, length: 1, kind: .punctuation))
                i += 1
            }
            let nameStart = i
            while i < n, !isWhitespace(u[i]), u[i] != greaterThan, u[i] != slash { i += 1 }
            if i > nameStart {
                tokens.append(Token(location: nameStart, length: i - nameStart, kind: .tagName))
            }

            while i < n {
                while i < n, isWhitespace(u[i]) { i += 1 }
                guard i < n else { break }
                if u[i] == greaterThan {
                    tokens.append(Token(location: i, length: 1, kind: .punctuation))
                    i += 1
                    break
                }
                if u[i] == slash {
                    let start = i
                    i += 1
                    if i < n, u[i] == greaterThan { i += 1 }
                    tokens.append(Token(location: start, length: i - start, kind: .punctuation))
                    break
                }
                let attrStart = i
                while i < n, !isWhitespace(u[i]), u[i] != equals, u[i] != greaterThan, u[i] != slash { i += 1 }
                if i > attrStart {
                    tokens.append(Token(location: attrStart, length: i - attrStart, kind: .attributeName))
                }
                while i < n, isWhitespace(u[i]) { i += 1 }
                guard i < n, u[i] == equals else { continue }
                tokens.append(Token(location: i, length: 1, kind: .punctuation))
                i += 1
                while i < n, isWhitespace(u[i]) { i += 1 }
                guard i < n, u[i] == quote || u[i] == apostrophe else { continue }
                let delimiter = u[i]
                let valueStart = i
                i += 1
                while i < n, u[i] != delimiter { i += 1 }
                i = min(i + 1, n)
                tokens.append(Token(location: valueStart, length: i - valueStart, kind: .attributeValue))
            }
        }
        return tokens
    }
}
