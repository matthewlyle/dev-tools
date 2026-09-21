import Foundation

/// JSON parsed with member order intact. `JSONSerialization` returns
/// unordered dictionaries, which would scramble child-element order relative
/// to the XML form of the same response. Numbers keep their source text.
indirect enum JSONValue: Sendable, Hashable {
    case object([(key: String, value: JSONValue)])
    case array([JSONValue])
    case string(String)
    case number(String)
    case bool(Bool)
    case null

    static func == (lhs: JSONValue, rhs: JSONValue) -> Bool {
        switch (lhs, rhs) {
        case (.object(let a), .object(let b)):
            a.count == b.count && zip(a, b).allSatisfy { $0.key == $1.key && $0.value == $1.value }
        case (.array(let a), .array(let b)): a == b
        case (.string(let a), .string(let b)): a == b
        case (.number(let a), .number(let b)): a == b
        case (.bool(let a), .bool(let b)): a == b
        case (.null, .null): true
        default: false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .object(let members):
            hasher.combine(0)
            for member in members {
                hasher.combine(member.key)
                hasher.combine(member.value)
            }
        case .array(let items):
            hasher.combine(1)
            hasher.combine(items)
        case .string(let s):
            hasher.combine(2)
            hasher.combine(s)
        case .number(let n):
            hasher.combine(3)
            hasher.combine(n)
        case .bool(let b):
            hasher.combine(4)
            hasher.combine(b)
        case .null:
            hasher.combine(5)
        }
    }

    static func parse(_ data: Data) -> JSONValue? {
        var parser = Parser(bytes: [UInt8](data))
        parser.skipWhitespace()
        guard let value = parser.parseValue() else { return nil }
        parser.skipWhitespace()
        return parser.atEnd ? value : nil
    }

    private struct Parser {
        let bytes: [UInt8]
        var index = 0

        init(bytes: [UInt8]) {
            self.bytes = bytes
        }

        var atEnd: Bool { index >= bytes.count }

        mutating func skipWhitespace() {
            while index < bytes.count, bytes[index] == 0x20 || bytes[index] == 0x09 || bytes[index] == 0x0A || bytes[index] == 0x0D {
                index += 1
            }
        }

        mutating func parseValue() -> JSONValue? {
            guard index < bytes.count else { return nil }
            switch bytes[index] {
            case 0x7B: return parseObject()
            case 0x5B: return parseArray()
            case 0x22: return parseString().map(JSONValue.string)
            case 0x74: return literal("true", .bool(true))
            case 0x66: return literal("false", .bool(false))
            case 0x6E: return literal("null", .null)
            default: return parseNumber()
            }
        }

        private mutating func literal(_ text: String, _ value: JSONValue) -> JSONValue? {
            let expected = Array(text.utf8)
            guard index + expected.count <= bytes.count, Array(bytes[index..<index + expected.count]) == expected else { return nil }
            index += expected.count
            return value
        }

        private mutating func parseObject() -> JSONValue? {
            index += 1
            var members: [(key: String, value: JSONValue)] = []
            skipWhitespace()
            if index < bytes.count, bytes[index] == 0x7D {
                index += 1
                return .object(members)
            }
            while index < bytes.count {
                skipWhitespace()
                guard let key = parseString() else { return nil }
                skipWhitespace()
                guard index < bytes.count, bytes[index] == 0x3A else { return nil }
                index += 1
                skipWhitespace()
                guard let value = parseValue() else { return nil }
                members.append((key, value))
                skipWhitespace()
                guard index < bytes.count else { return nil }
                if bytes[index] == 0x2C {
                    index += 1
                    continue
                }
                if bytes[index] == 0x7D {
                    index += 1
                    return .object(members)
                }
                return nil
            }
            return nil
        }

        private mutating func parseArray() -> JSONValue? {
            index += 1
            var items: [JSONValue] = []
            skipWhitespace()
            if index < bytes.count, bytes[index] == 0x5D {
                index += 1
                return .array(items)
            }
            while index < bytes.count {
                skipWhitespace()
                guard let value = parseValue() else { return nil }
                items.append(value)
                skipWhitespace()
                guard index < bytes.count else { return nil }
                if bytes[index] == 0x2C {
                    index += 1
                    continue
                }
                if bytes[index] == 0x5D {
                    index += 1
                    return .array(items)
                }
                return nil
            }
            return nil
        }

        private mutating func parseString() -> String? {
            guard index < bytes.count, bytes[index] == 0x22 else { return nil }
            index += 1
            var out: [UInt8] = []
            while index < bytes.count {
                let c = bytes[index]
                if c == 0x22 {
                    index += 1
                    return String(decoding: out, as: UTF8.self)
                }
                if c == 0x5C {
                    index += 1
                    guard index < bytes.count else { return nil }
                    switch bytes[index] {
                    case 0x22: out.append(0x22)
                    case 0x5C: out.append(0x5C)
                    case 0x2F: out.append(0x2F)
                    case 0x62: out.append(0x08)
                    case 0x66: out.append(0x0C)
                    case 0x6E: out.append(0x0A)
                    case 0x72: out.append(0x0D)
                    case 0x74: out.append(0x09)
                    case 0x75:
                        guard let scalar = parseUnicodeEscape() else { return nil }
                        out.append(contentsOf: Array(String(Character(scalar)).utf8))
                        continue
                    default: return nil
                    }
                    index += 1
                } else {
                    out.append(c)
                    index += 1
                }
            }
            return nil
        }

        /// Called with `index` on the `u`; consumes `uXXXX` and a trailing
        /// low surrogate escape when present.
        private mutating func parseUnicodeEscape() -> Unicode.Scalar? {
            func hex4(at start: Int) -> UInt32? {
                guard start + 4 <= bytes.count else { return nil }
                var value: UInt32 = 0
                for i in start..<start + 4 {
                    let c = bytes[i]
                    let digit: UInt32
                    switch c {
                    case 0x30...0x39: digit = UInt32(c - 0x30)
                    case 0x41...0x46: digit = UInt32(c - 0x41 + 10)
                    case 0x61...0x66: digit = UInt32(c - 0x61 + 10)
                    default: return nil
                    }
                    value = value << 4 | digit
                }
                return value
            }

            guard let high = hex4(at: index + 1) else { return nil }
            index += 5
            if (0xD800...0xDBFF).contains(high),
               index + 1 < bytes.count, bytes[index] == 0x5C, bytes[index + 1] == 0x75,
               let low = hex4(at: index + 2), (0xDC00...0xDFFF).contains(low) {
                index += 6
                let combined = 0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00)
                return Unicode.Scalar(combined)
            }
            return Unicode.Scalar(high) ?? Unicode.Scalar(0xFFFD)
        }

        private mutating func parseNumber() -> JSONValue? {
            let start = index
            while index < bytes.count {
                let c = bytes[index]
                guard (c >= 0x30 && c <= 0x39) || c == 0x2D || c == 0x2B || c == 0x2E || c == 0x65 || c == 0x45 else { break }
                index += 1
            }
            guard index > start else { return nil }
            return .number(String(decoding: bytes[start..<index], as: UTF8.self))
        }
    }
}
