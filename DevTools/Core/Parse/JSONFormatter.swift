import Foundation

/// Re-indents JSON without parsing it into a dictionary, so key order and
/// number formatting come out exactly as the server sent them.
enum JSONFormatter {
    private static let quote: UInt8 = 0x22
    private static let backslash: UInt8 = 0x5C
    private static let colon: UInt8 = 0x3A
    private static let comma: UInt8 = 0x2C
    private static let openBrace: UInt8 = 0x7B
    private static let closeBrace: UInt8 = 0x7D
    private static let openBracket: UInt8 = 0x5B
    private static let closeBracket: UInt8 = 0x5D
    private static let newline: UInt8 = 0x0A
    private static let space: UInt8 = 0x20

    private static func isWhitespace(_ c: UInt8) -> Bool {
        c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D
    }

    static func pretty(_ data: Data, indent: Int = 2) -> String {
        let input = [UInt8](data)
        let n = input.count
        var out: [UInt8] = []
        out.reserveCapacity(n + n / 2)
        var depth = 0
        var i = 0

        func writeIndent() {
            out.append(newline)
            out.append(contentsOf: repeatElement(space, count: depth * indent))
        }

        func nextNonWhitespace(after index: Int) -> UInt8? {
            var j = index
            while j < n, isWhitespace(input[j]) { j += 1 }
            return j < n ? input[j] : nil
        }

        while i < n {
            let c = input[i]
            switch c {
            case quote:
                let start = i
                i += 1
                while i < n, input[i] != quote {
                    i += input[i] == backslash ? 2 : 1
                }
                i = min(i + 1, n)
                out.append(contentsOf: input[start..<i])
            case openBrace, openBracket:
                out.append(c)
                let closer = c == openBrace ? closeBrace : closeBracket
                if nextNonWhitespace(after: i + 1) == closer {
                    var j = i + 1
                    while j < n, isWhitespace(input[j]) { j += 1 }
                    out.append(closer)
                    i = j + 1
                } else {
                    depth += 1
                    writeIndent()
                    i += 1
                }
            case closeBrace, closeBracket:
                depth = max(depth - 1, 0)
                writeIndent()
                out.append(c)
                i += 1
            case comma:
                out.append(c)
                writeIndent()
                i += 1
            case colon:
                out.append(c)
                out.append(space)
                i += 1
            default:
                if !isWhitespace(c) { out.append(c) }
                i += 1
            }
        }
        return String(decoding: out, as: UTF8.self)
    }
}
