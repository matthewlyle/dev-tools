import AppKit
import SwiftUI

/// Read-only monospaced text with token colouring and code folding.
/// NSTextView handles multi-megabyte bodies, selection, and ⌘F where SwiftUI
/// `Text` can't. Folding is rendered by substituting collapsed spans with a
/// `⋯ N` placeholder; openers and placeholders carry `fold://` links.
struct CodeTextView: NSViewRepresentable {
    let text: String
    let tokens: [Token]
    let folds: [FoldRegion]
    @Binding var collapsed: Set<Int>
    let wrap: Bool
    /// Changes when the underlying response changes.
    let version: Date

    final class Coordinator: NSObject, NSTextViewDelegate {
        var appliedVersion: Date?
        var appliedCollapsed: Set<Int>?
        var appliedWrap: Bool?
        var toggle: ((Int) -> Void)?
        var renderTask: Task<Void, Never>?

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let url = link as? URL, url.scheme == "fold", let id = Int(url.host() ?? "") else { return false }
            toggle?(id)
            return true
        }
    }

    /// Carries the built string back from the render thread. Attributed
    /// strings are safe to build in isolation and hand over once.
    private struct Rendered: @unchecked Sendable {
        let string: NSAttributedString
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let textView = scrollView.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.allowsUndo = false
        textView.font = Self.font
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isVerticallyResizable = true
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        // Links keep the token colour; only the cursor gives them away.
        textView.linkTextAttributes = [.cursor: NSCursor.pointingHand]
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let coordinator = context.coordinator
        coordinator.toggle = { id in
            if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
        }

        let versionChanged = coordinator.appliedVersion != version
        if versionChanged || coordinator.appliedCollapsed != collapsed {
            coordinator.appliedVersion = version
            coordinator.appliedCollapsed = collapsed
            coordinator.renderTask?.cancel()

            let text = text, tokens = tokens, folds = folds, collapsed = collapsed, version = version
            coordinator.renderTask = Task { @MainActor in
                let rendered = await Task.detached(priority: .userInitiated) {
                    Self.render(text: text, tokens: tokens, folds: folds, collapsed: collapsed)
                }.value
                // A newer response or fold change superseded this render.
                guard !Task.isCancelled,
                      coordinator.appliedVersion == version,
                      coordinator.appliedCollapsed == collapsed
                else { return }
                let visibleRect = scrollView.contentView.bounds
                textView.textStorage?.setAttributedString(rendered.string)
                if versionChanged {
                    textView.scroll(.zero)
                } else {
                    scrollView.contentView.scroll(to: visibleRect.origin)
                    scrollView.reflectScrolledClipView(scrollView.contentView)
                }
            }
        }

        if coordinator.appliedWrap != wrap {
            Self.applyWrap(wrap, to: textView, in: scrollView)
            coordinator.appliedWrap = wrap
        }
    }

    // MARK: Rendering

    private static let font = Typeface.code(size: 12)
    private static let placeholderAttributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.secondaryLabelColor,
        .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.25),
    ]

    /// Builds the displayed string: original text with each effective
    /// collapsed region replaced by a placeholder, token colours re-applied at
    /// shifted offsets, and fold links on anchors and placeholders.
    private nonisolated static func render(text: String, tokens: [Token], folds: [FoldRegion], collapsed: Set<Int>) -> Rendered {
        let source = text as NSString
        let base: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
        let result = NSMutableAttributedString()
        result.beginEditing()
        defer { result.endEditing() }
        let hidden = Folding.effective(folds, collapsed: collapsed)

        var cursor = 0
        var tokenIndex = 0

        func appendSegment(_ start: Int, _ end: Int) {
            guard end > start else { return }
            let offset = result.length - start
            result.append(NSAttributedString(string: source.substring(with: NSRange(location: start, length: end - start)), attributes: base))
            while tokenIndex < tokens.count, tokens[tokenIndex].location < start { tokenIndex += 1 }
            var index = tokenIndex
            while index < tokens.count, tokens[index].location < end {
                let token = tokens[index]
                let clippedEnd = min(token.location + token.length, end)
                if clippedEnd > token.location {
                    result.addAttribute(.foregroundColor, value: color(for: token.kind), range: NSRange(location: token.location + offset, length: clippedEnd - token.location))
                }
                index += 1
            }
            tokenIndex = index
        }

        // Anchors are clickable whether or not their region is collapsed.
        var anchorOffsets: [(region: FoldRegion, offset: Int)] = []
        var anchorIndex = 0
        let anchorsByStart = folds.sorted { $0.anchor.location < $1.anchor.location }

        func recordAnchors(upTo end: Int, offset: Int) {
            while anchorIndex < anchorsByStart.count, anchorsByStart[anchorIndex].anchor.location < end {
                let region = anchorsByStart[anchorIndex]
                if region.anchor.location >= cursor {
                    anchorOffsets.append((region, offset))
                }
                anchorIndex += 1
            }
        }

        for region in hidden {
            let offset = result.length - cursor
            recordAnchors(upTo: region.hiddenStart, offset: offset)
            appendSegment(cursor, region.hiddenStart)
            let placeholder = NSMutableAttributedString(string: " ⋯ \(region.count) ", attributes: placeholderAttributes)
            placeholder.addAttribute(.link, value: URL(string: "fold://\(region.id)")!, range: NSRange(location: 0, length: placeholder.length))
            result.append(placeholder)
            cursor = region.hiddenEnd
            // Skip anchors that were inside the hidden span.
            while anchorIndex < anchorsByStart.count, anchorsByStart[anchorIndex].anchor.location < cursor { anchorIndex += 1 }
        }
        let tailOffset = result.length - cursor
        recordAnchors(upTo: source.length, offset: tailOffset)
        appendSegment(cursor, source.length)

        for (region, offset) in anchorOffsets {
            let range = NSRange(location: region.anchor.location + offset, length: region.anchor.length)
            guard range.location + range.length <= result.length else { continue }
            result.addAttribute(.link, value: URL(string: "fold://\(region.id)")!, range: range)
        }
        return Rendered(string: result)
    }

    private nonisolated static func color(for kind: TokenKind) -> NSColor {
        switch kind {
        case .key, .attributeName: .systemTeal
        case .string, .attributeValue: .systemGreen
        case .number: .systemPurple
        case .literal: .systemOrange
        case .punctuation: .secondaryLabelColor
        case .tagName: .systemBlue
        case .comment, .processingInstruction: .tertiaryLabelColor
        }
    }

    private static func applyWrap(_ wrap: Bool, to textView: NSTextView, in scrollView: NSScrollView) {
        guard let container = textView.textContainer else { return }
        if wrap {
            container.widthTracksTextView = true
            container.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            textView.frame.size.width = scrollView.contentSize.width
        } else {
            container.widthTracksTextView = false
            container.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textView.isHorizontallyResizable = true
            textView.autoresizingMask = []
        }
        textView.needsLayout = true
    }
}
