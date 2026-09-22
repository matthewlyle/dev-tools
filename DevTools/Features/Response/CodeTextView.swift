import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The response body. `header` rides inside the text view's scroll — pinned
/// above the text by a top content inset — so it scrolls away with the body
/// while the body keeps viewport layout (a page-level scroll view would lay
/// the whole document out).
struct CodeTextView {
    let text: String
    let tokens: [Token]
    let folds: [FoldRegion]
    @Binding var collapsed: Set<Int>
    let wrap: Bool
    let version: Date
    let header: AnyView

    @MainActor final class Coordinator: NSObject {
        var appliedVersion: Date?
        var appliedCollapsed: Set<Int>?
        var appliedWrap: Bool?
        var toggle: ((Int) -> Void)?
        var renderTask: Task<Void, Never>?
        var headerHeight: CGFloat = 0
        var headerWidth: CGFloat?
        /// Re-lays the header out after its content changed height from
        /// inside the hosted tree (a parameter row added or removed), which
        /// the representable's update never sees.
        var relayoutHeader: (() -> Void)?
        #if os(macOS)
        var headerHost: NSHostingController<AnyView>?
        var frameObserver: NSObjectProtocol?
        #else
        var headerHost: UIHostingController<AnyView>?
        #endif
    }

    /// The header as hosted: environment handed over (the hosted tree is
    /// outside SwiftUI's hierarchy) and its height watched.
    private func hostedHeader(_ coordinator: Coordinator, environment: EnvironmentValues) -> AnyView {
        AnyView(
            header
                .environment(\.self, environment)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    if abs(height - coordinator.headerHeight) > 0.5 { coordinator.relayoutHeader?() }
                }
        )
    }

    /// Carries the built string back from the render thread. Attributed
    /// strings are safe to build in isolation and hand over once.
    private struct Rendered: @unchecked Sendable {
        let string: NSAttributedString
    }

    private nonisolated(unsafe) static let font = Typeface.code(size: 12)
    private nonisolated(unsafe) static let placeholderAttributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: PlatformColor.codeSecondaryLabel,
        .backgroundColor: PlatformColor.codeQuaternaryLabel.withAlphaComponent(0.25),
    ]

    private nonisolated static func render(text: String, tokens: [Token], folds: [FoldRegion], collapsed: Set<Int>) -> Rendered {
        let source = text as NSString
        let base: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: PlatformColor.codeLabel]
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

    private nonisolated static func color(for kind: TokenKind) -> PlatformColor {
        switch kind {
        case .key, .attributeName: .systemTeal
        case .string, .attributeValue: .systemGreen
        case .number: .systemPurple
        case .literal: .systemOrange
        case .punctuation: .codeSecondaryLabel
        case .tagName: .systemBlue
        case .comment, .processingInstruction: .codeTertiaryLabel
        }
    }
}

#if os(macOS)
extension CodeTextView.Coordinator: NSTextViewDelegate {
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard let url = link as? URL, url.scheme == "fold", let id = Int(url.host() ?? "") else { return false }
        toggle?(id)
        return true
    }
}

extension CodeTextView: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .codeBackground

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
        textView.linkTextAttributes = [.cursor: NSCursor.pointingHand]

        // contentInsets inset the clip view's frame, so a header placed above
        // the document sits outside the clip view's bounds: it still draws
        // (views don't clip subviews) but the default hit test ignores it.
        scrollView.automaticallyAdjustsContentInsets = false
        let clipView = HeaderClipView()
        clipView.drawsBackground = false
        scrollView.contentView = clipView
        scrollView.documentView = textView
        let host = NSHostingController(rootView: AnyView(EmptyView()))
        host.sizingOptions = []
        clipView.addSubview(host.view)
        clipView.header = host.view
        context.coordinator.headerHost = host
        scrollView.contentView.postsFrameChangedNotifications = true
        context.coordinator.frameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification, object: scrollView.contentView, queue: .main
        ) { [weak scrollView, coordinator = context.coordinator] _ in
            MainActor.assumeIsolated {
                guard let scrollView else { return }
                Self.layoutHeader(in: scrollView, coordinator: coordinator)
            }
        }
        return scrollView
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        if let observer = coordinator.frameObserver { NotificationCenter.default.removeObserver(observer) }
    }

    /// Header width follows the clip view; its height is what SwiftUI wants
    /// at that width, and the document is inset by exactly that.
    @MainActor private static func layoutHeader(in scrollView: NSScrollView, coordinator: Coordinator, force: Bool = false) {
        guard let host = coordinator.headerHost else { return }
        let width = scrollView.contentView.bounds.width
        guard force || coordinator.headerWidth != width else { return }
        let wasAtTop = scrollView.contentView.bounds.origin.y <= 1
        coordinator.headerWidth = width
        coordinator.headerHeight = host.sizeThatFits(in: NSSize(width: width, height: .greatestFiniteMagnitude)).height
        host.view.frame = NSRect(x: 0, y: -coordinator.headerHeight, width: width, height: coordinator.headerHeight)
        scrollView.contentInsets = NSEdgeInsets(top: coordinator.headerHeight, left: 0, bottom: 0, right: 0)
        if wasAtTop { scrollToTop(scrollView, coordinator: coordinator) }
    }

    @MainActor private static func scrollToTop(_ scrollView: NSScrollView, coordinator: Coordinator) {
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: -coordinator.headerHeight))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let coordinator = context.coordinator
        coordinator.toggle = { id in
            if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
        }
        // The hosted header is outside SwiftUI's tree, so it gets the
        // environment (stores, styles) handed over explicitly.
        coordinator.headerHost?.rootView = hostedHeader(coordinator, environment: context.environment)
        coordinator.relayoutHeader = { [weak scrollView] in
            guard let scrollView else { return }
            Self.layoutHeader(in: scrollView, coordinator: coordinator, force: true)
        }
        Self.layoutHeader(in: scrollView, coordinator: coordinator, force: true)

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
                guard !Task.isCancelled,
                      coordinator.appliedVersion == version,
                      coordinator.appliedCollapsed == collapsed
                else { return }
                let visibleRect = scrollView.contentView.bounds
                textView.textStorage?.setAttributedString(rendered.string)
                if versionChanged {
                    Self.scrollToTop(scrollView, coordinator: coordinator)
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

/// Routes clicks to the header hosted above the document, which lies
/// outside the clip view's bounds once `contentInsets` push the frame down.
final class HeaderClipView: NSClipView {
    weak var header: NSView?

    override func hitTest(_ point: NSPoint) -> NSView? {
        if let header, let superview {
            let local = convert(point, from: superview)
            if header.frame.contains(local) {
                return header.hitTest(local)
            }
        }
        return super.hitTest(point)
    }
}
#else
extension CodeTextView.Coordinator: UITextViewDelegate {
    func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
        if case let .link(url) = textItem.content, url.scheme == "fold", let host = url.host(), let id = Int(host) {
            return UIAction { [weak self] _ in self?.toggle?(id) }
        }
        return defaultAction
    }
}

/// Positions the hosted header above the text and keeps the top inset equal
/// to its height, re-measuring when the width changes.
final class HeaderedTextView: UITextView {
    var headerView: UIView?
    var measureHeader: ((CGFloat) -> CGFloat)?
    private(set) var headerHeight: CGFloat = 0
    private var measuredWidth: CGFloat?

    func invalidateHeader() {
        measuredWidth = nil
        setNeedsLayout()
    }

    var topOffset: CGPoint { CGPoint(x: 0, y: -headerHeight) }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let headerView, let measureHeader else { return }
        let width = bounds.width
        guard measuredWidth != width else { return }
        let wasAtTop = contentOffset.y <= -headerHeight + 1
        measuredWidth = width
        headerHeight = measureHeader(width)
        headerView.frame = CGRect(x: 0, y: -headerHeight, width: width, height: headerHeight)
        contentInset.top = headerHeight
        verticalScrollIndicatorInsets.top = headerHeight
        if wasAtTop { contentOffset = topOffset }
    }
}

extension CodeTextView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> HeaderedTextView {
        let textView = HeaderedTextView()
        textView.delegate = context.coordinator
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .codeBackground
        textView.font = Self.font
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        textView.textContainer.lineFragmentPadding = 0
        textView.alwaysBounceVertical = true
        textView.isFindInteractionEnabled = true
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.spellCheckingType = .no
        textView.contentInsetAdjustmentBehavior = .never

        let host = UIHostingController(rootView: AnyView(EmptyView()))
        host.view.backgroundColor = .clear
        textView.addSubview(host.view)
        textView.headerView = host.view
        textView.measureHeader = { [host] width in
            host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
        }
        context.coordinator.headerHost = host
        return textView
    }

    func updateUIView(_ textView: HeaderedTextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.toggle = { id in
            if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
        }
        // The hosted header is outside SwiftUI's tree, so it gets the
        // environment (stores, styles) handed over explicitly.
        coordinator.headerHost?.rootView = hostedHeader(coordinator, environment: context.environment)
        coordinator.relayoutHeader = { [weak textView] in textView?.invalidateHeader() }
        textView.invalidateHeader()

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
                guard !Task.isCancelled,
                      coordinator.appliedVersion == version,
                      coordinator.appliedCollapsed == collapsed
                else { return }
                let offset = textView.contentOffset
                textView.attributedText = rendered.string
                textView.setContentOffset(versionChanged ? textView.topOffset : offset, animated: false)
            }
        }

        if coordinator.appliedWrap != wrap {
            Self.applyWrap(wrap, to: textView)
            coordinator.appliedWrap = wrap
        }
    }

    @MainActor private static func applyWrap(_ wrap: Bool, to textView: UITextView) {
        let container = textView.textContainer
        if wrap {
            container.widthTracksTextView = true
            container.size = CGSize(width: textView.bounds.width, height: CGFloat.greatestFiniteMagnitude)
        } else {
            // Unbounded width lays the code on one line; the text view scrolls
            // horizontally to reach it.
            container.widthTracksTextView = false
            container.size = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }
    }
}
#endif
