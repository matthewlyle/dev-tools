import Foundation

struct FoldRegion: Sendable, Hashable, Identifiable {
    let id: Int
    let anchor: NSRange
    let hiddenStart: Int
    let hiddenEnd: Int
    let count: Int
    let depth: Int
}

enum Folding {
    static func jsonRegions(text: String, tokens: [Token]) -> [FoldRegion] {
        let utf16 = Array(text.utf16)
        struct Frame {
            let opener: Token
            var count = 0
        }
        var stack: [Frame] = []
        var regions: [FoldRegion] = []

        var skipCloser = false
        for (index, token) in tokens.enumerated() where token.kind == .punctuation {
            switch utf16[token.location] {
            case 0x7B, 0x5B:
                if index + 1 < tokens.count, tokens[index + 1].kind == .punctuation,
                   utf16[tokens[index + 1].location] == 0x7D || utf16[tokens[index + 1].location] == 0x5D {
                    skipCloser = true
                    continue
                }
                stack.append(Frame(opener: token))
            case 0x2C:
                if !stack.isEmpty { stack[stack.count - 1].count += 1 }
            case 0x7D, 0x5D:
                if skipCloser {
                    skipCloser = false
                    continue
                }
                guard let frame = stack.popLast() else { continue }
                regions.append(FoldRegion(
                    id: regions.count,
                    anchor: frame.opener.nsRange,
                    hiddenStart: frame.opener.location + 1,
                    hiddenEnd: token.location,
                    count: frame.count + 1,
                    depth: stack.count
                ))
            default:
                continue
            }
        }
        return finish(regions)
    }

    static func xmlRegions(text: String, tokens: [Token]) -> [FoldRegion] {
        let utf16 = Array(text.utf16)
        struct Frame {
            let name: Token
            var contentStart: Int?
            var count = 0
        }
        var stack: [Frame] = []
        var regions: [FoldRegion] = []
        var index = 0

        while index < tokens.count {
            let token = tokens[index]
            defer { index += 1 }
            guard token.kind == .punctuation else { continue }
            let first = utf16[token.location]

            if first == 0x3C {
                let next = index + 1 < tokens.count ? tokens[index + 1] : nil
                if let next, next.kind == .punctuation, utf16[next.location] == 0x2F {
                    guard let frame = stack.popLast(), let start = frame.contentStart else { continue }
                    if token.location > start {
                        regions.append(FoldRegion(
                            id: regions.count,
                            anchor: frame.name.nsRange,
                            hiddenStart: start,
                            hiddenEnd: token.location,
                            count: frame.count,
                            depth: stack.count
                        ))
                    }
                } else if let next, next.kind == .tagName {
                    if !stack.isEmpty { stack[stack.count - 1].count += 1 }
                    stack.append(Frame(name: next))
                }
            } else if first == 0x3E, !stack.isEmpty, stack[stack.count - 1].contentStart == nil {
                stack[stack.count - 1].contentStart = token.location + 1
            } else if first == 0x2F, token.length == 2, !stack.isEmpty, stack[stack.count - 1].contentStart == nil {
                stack.removeLast()
            }
        }
        return finish(regions)
    }

    private static func finish(_ regions: [FoldRegion]) -> [FoldRegion] {
        regions
            .sorted { $0.hiddenStart < $1.hiddenStart }
            .enumerated()
            .map { FoldRegion(id: $0.offset, anchor: $0.element.anchor, hiddenStart: $0.element.hiddenStart, hiddenEnd: $0.element.hiddenEnd, count: $0.element.count, depth: $0.element.depth) }
    }

    static func effective(_ regions: [FoldRegion], collapsed: Set<Int>) -> [FoldRegion] {
        var result: [FoldRegion] = []
        var hiddenUntil = -1
        for region in regions where collapsed.contains(region.id) {
            guard region.hiddenStart >= hiddenUntil else { continue }
            result.append(region)
            hiddenUntil = region.hiddenEnd
        }
        return result
    }
}
