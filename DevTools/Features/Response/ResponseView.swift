import SwiftUI

enum ResponseTab: String, CaseIterable, Identifiable {
    case raw = "Response"
    case headers = "Headers"

    var id: String { rawValue }
}

struct ResponseView<RequestBar: View>: View {
    let server: ConnectedServer?
    let editable: Bool
    @ViewBuilder let requestBar: () -> RequestBar

    @Environment(RequestStore.self) private var requests
    @Environment(SpecStore.self) private var spec
    @AppStorage("responseTab") private var tab: ResponseTab = .raw
    @State private var collapsed: Set<Int> = []

    /// The spec often omits `required`, so a 400 offers every documented parameter not sent.
    private var missingParameterHint: [SpecParameter]? {
        guard let response = requests.response, response.status == 400,
              let operation = spec.operation(matching: requests.current.path)
        else { return nil }
        let present = Set(requests.current.query.filter(\.enabled).map { $0.name.lowercased() })
        let candidates = operation.queryParameters.filter { !present.contains($0.name.lowercased()) }
        return candidates.isEmpty ? nil : candidates
    }

    private var adminOnlyHint: SpecOperation? {
        guard let response = requests.response, response.status == 403, server?.owned == false,
              let operation = spec.operation(matching: requests.current.path), operation.access == .admin
        else { return nil }
        return operation
    }

    var body: some View {
        // Only the resting and error states transition: a transition on the text view forces a
        // full-document layout.
        ZStack {
            if let response = requests.response, let document = requests.document {
                Group {
                    switch tab {
                    case .raw:
                        RawResponseView(document: document, response: response, collapsed: $collapsed) {
                            headerBlock
                        }
                    case .headers:
                        HeadersView(response: response, server: server, editable: editable) {
                            headerBlock
                        }
                    }
                }
                .transition(.identity)
            } else if !editable && requests.lastSent == nil {
                FillingScrollView { EmptyView() }
                    .restingStateTransition()
                    .zIndex(1)
            } else {
                FillingScrollView {
                    headerBlock
                    ZStack {
                        if let error = requests.errorMessage {
                            ContentUnavailableView(
                                "Request Failed",
                                systemImage: "exclamationmark.triangle",
                                description: Text(error)
                            )
                            .restingStateTransition(rising: true)
                        } else if requests.isSending {
                            ProgressView()
                        } else {
                            ZeroState(text: editable
                                ? "Send a request to see the response here."
                                : "Select a request to see the response here.")
                            .restingStateTransition(rising: true)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .restingStateTransition()
                .zIndex(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: requests.document?.version) { _, _ in
            collapsed = []
        }
    }

    @ViewBuilder
    private var headerBlock: some View {
        VStack(spacing: 0) {
            requestBar()
            if let response = requests.response {
                Divider()
                ResponseInfoRow(
                    response: response,
                    pagination: requests.pagination,
                    server: server,
                    notice: tab == .raw ? requests.document?.notice : nil,
                    controls: tab == .raw ? requests.document.map { BodyControls(document: $0, response: response) } : nil
                ) {
                    Picker("View", selection: $tab) {
                        ForEach(ResponseTab.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
        .background(.fill.tertiary, in: .rect(cornerRadius: 12))
        .padding(12)

        if requests.response != nil {
            if let hint = missingParameterHint {
                MissingParametersHint(parameters: hint) {
                    for parameter in hint where requests.current.query.allSatisfy({ $0.name != parameter.name }) {
                        requests.current.query.append(QueryParam(name: parameter.name, value: parameter.suggestedValue))
                    }
                }
            }
            if let operation = adminOnlyHint {
                AccessHint(operation: operation)
            }
        }
    }
}

/// On macOS the toolbar turns transparent only over a scroll view, so static states go through one too.
/// Content pins to the top: while the viewport resizes it can briefly be shorter than the minimum, and a
/// centred frame would float the request bar down the screen.
struct FillingScrollView<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    content()
                }
                .frame(minHeight: proxy.size.height, alignment: .top)
            }
        }
    }
}

struct ZeroState<Action: View>: View {
    let text: String
    @ViewBuilder let action: () -> Action

    var body: some View {
        VStack(spacing: 12) {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            action()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension ZeroState where Action == EmptyView {
    init(text: String) {
        self.init(text: text) { EmptyView() }
    }
}

extension View {
    func restingStateTransition(rising: Bool = false) -> some View {
        modifier(RestingStateTransition(rising: rising))
    }
}

private struct RestingStateTransition: ViewModifier {
    let rising: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transition(transition)
    }

    private var transition: AnyTransition {
        if reduceMotion { return .identity }
        let insertion: AnyTransition = rising ? .opacity.combined(with: .offset(y: 6)) : .opacity
        return .asymmetric(
            insertion: insertion.animation(.snappy(duration: 0.3)),
            removal: .opacity.animation(.smooth(duration: 0.1))
        )
    }
}

private struct MissingParametersHint: View {
    let parameters: [SpecParameter]
    let add: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Bad Request — this endpoint documents \(parameters.count) parameter\(parameters.count == 1 ? "" : "s") you haven't sent.")
                    .font(.callout)
                Text(parameters.map(\.name).joined(separator: ", "))
                    .font(.code(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
            Button("Add Parameters", action: add)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.08))
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct AccessHint: View {
    let operation: SpecOperation

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Forbidden — “\(operation.summary)” is admin-only, and this server is shared with you.")
                    .font(.callout)
                Text("Only the server's owner can call it. Try it on a server you own.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.08))
        .overlay(alignment: .bottom) { Divider() }
    }
}

struct ResponseInfoRow<Tabs: View>: View {
    let response: PlexResponse
    let pagination: PaginationInfo?
    let server: ConnectedServer?
    var notice: String? = nil
    var controls: BodyControls? = nil
    @ViewBuilder let tabs: () -> Tabs

    @Environment(\.isCompactWidth) private var compact

    var body: some View {
        InfoRowLayout(stacked: compact, hasSecondary: pagination != nil || notice != nil || (!compact && controls != nil)) {
            ResponseStatusBar(response: response)
            HStack(spacing: 10) {
                secondary
            }
            HStack(spacing: 10) {
                tabs()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var secondary: some View {
        if let pagination {
            PaginationControls(pagination: pagination, server: server)
        }
        if let notice {
            ViewThatFits(in: .horizontal) {
                Text(notice)
                    .lineLimit(1)
                    .fixedSize()
                Label(notice, systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(.iconOnly)
            }
            .font(.caption)
            .foregroundStyle(.orange)
            .help(notice)
        }
        Spacer()
        if !compact { controls }
    }
}

/// One line while the status can keep at least its code, else status and tabs over the rest.
/// A `ViewThatFits` would do it but stop the numbers rolling.
private struct InfoRowLayout: Layout {
    let stacked: Bool
    let hasSecondary: Bool
    private let spacing: CGFloat = 10
    private let lineSpacing: CGFloat = 8

    private struct Measures {
        let statusMin: CGFloat
        let secondaryMin: CGSize
        let tabs: CGSize

        init(_ subviews: LayoutSubviews) {
            statusMin = subviews[0].sizeThatFits(ProposedViewSize(width: 0, height: nil)).width
            secondaryMin = subviews[1].sizeThatFits(ProposedViewSize(width: 0, height: nil))
            tabs = subviews[2].sizeThatFits(.unspecified)
        }
    }

    private func secondaryWidth(_ m: Measures) -> CGFloat {
        hasSecondary ? m.secondaryMin.width + spacing : 0
    }

    private func fitsOneLine(_ width: CGFloat, _ m: Measures) -> Bool {
        !stacked && m.statusMin + secondaryWidth(m) + spacing + m.tabs.width <= width
    }

    private func statusProposal(_ width: CGFloat, oneLine: Bool, _ m: Measures) -> ProposedViewSize {
        ProposedViewSize(width: max(width - m.tabs.width - spacing - (oneLine ? secondaryWidth(m) : 0), 0), height: nil)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let m = Measures(subviews)
        let width = proposal.width ?? .infinity
        let oneLine = fitsOneLine(width, m)
        let status = subviews[0].sizeThatFits(statusProposal(width, oneLine: oneLine, m))
        if oneLine {
            let natural = status.width + secondaryWidth(m) + spacing + m.tabs.width
            let height = max(status.height, m.tabs.height, hasSecondary ? m.secondaryMin.height : 0)
            return CGSize(width: proposal.width ?? natural, height: height)
        }
        let needed = max(m.statusMin + spacing + m.tabs.width, hasSecondary ? m.secondaryMin.width : 0)
        let height = max(status.height, m.tabs.height) + (hasSecondary ? lineSpacing + m.secondaryMin.height : 0)
        return CGSize(width: proposal.width.map { max($0, needed) } ?? needed, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let m = Measures(subviews)
        // Decided from the proposal, like `SheddingRow`: the placed bounds can come out a fraction narrower.
        let width = proposal.width ?? bounds.width
        let oneLine = fitsOneLine(width, m)
        let statusProposal = statusProposal(width, oneLine: oneLine, m)
        let status = subviews[0].sizeThatFits(statusProposal)
        let lineHeight = oneLine ? bounds.height : max(status.height, m.tabs.height)
        let midY = bounds.minY + lineHeight / 2
        subviews[0].place(at: CGPoint(x: bounds.minX, y: midY), anchor: .leading, proposal: statusProposal)
        subviews[2].place(at: CGPoint(x: bounds.maxX, y: midY), anchor: .trailing, proposal: .unspecified)
        guard hasSecondary else {
            subviews[1].place(at: CGPoint(x: bounds.maxX + 10_000, y: midY), anchor: .leading, proposal: .zero)
            return
        }
        if oneLine {
            let x = bounds.minX + status.width + spacing
            let width = max(bounds.maxX - m.tabs.width - spacing - x, 0)
            subviews[1].place(at: CGPoint(x: x, y: midY), anchor: .leading, proposal: ProposedViewSize(width: width, height: nil))
        } else {
            let y = bounds.minY + lineHeight + lineSpacing
            subviews[1].place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: nil))
        }
    }
}

struct PaginationControls: View {
    let pagination: PaginationInfo
    let server: ConnectedServer?

    @Environment(RequestStore.self) private var requests
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Action { case previous, next, all }
    @State private var pending: Action?

    var body: some View {
        HStack(spacing: 4) {
            Button {
                run(.previous) { requests.page(start: pagination.start - pagination.pageSize, size: pagination.pageSize, on: $0) }
            } label: {
                Label { Text("Previous Page") } icon: { progress(for: .previous) { Image(systemName: "chevron.left") } }
                    .labelStyle(.iconOnly)
            }
            .disabled(!pagination.hasPrevious || unavailable(for: .previous))
            .help("Previous page")

            Text(pagination.label)
                .font(.code(.callout))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                .contentTransition(.numericText(value: Double(pagination.end)))
                .help("Paged response: X-Plex-Container-Start / Total-Size")

            Button {
                run(.next) { requests.page(start: pagination.end, size: pagination.pageSize, on: $0) }
            } label: {
                Label { Text("Next Page") } icon: { progress(for: .next) { Image(systemName: "chevron.right") } }
                    .labelStyle(.iconOnly)
            }
            .disabled(!pagination.hasNext || unavailable(for: .next))
            .help("Next page")

            Button {
                run(.all) { requests.fetchAll(on: $0) }
            } label: {
                progress(for: .all) { Text("Fetch All") }
            }
            .font(.callout)
            .disabled((!pagination.hasPrevious && !pagination.hasNext) || unavailable(for: .all))
            .help("Send again without paging, to get every item in one response")
        }
        .onChange(of: requests.isSending) { _, sending in
            if !sending { pending = nil }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.fill.tertiary, in: .capsule)
        .fixedSize()
        .animation(reduceMotion ? nil : .snappy, value: pagination)
    }

    /// The pressed button stays enabled so its spinner isn't dimmed; `run` ignores a second press.
    private func unavailable(for action: Action) -> Bool {
        server == nil || (requests.isSending && pending != action)
    }

    private func run(_ action: Action, _ fetch: (ConnectedServer) -> Void) {
        guard let server, !requests.isSending else { return }
        pending = action
        fetch(server)
    }

    private func progress(for action: Action, @ViewBuilder _ content: () -> some View) -> some View {
        content()
            .opacity(pending == action ? 0 : 1)
            .overlay {
                if pending == action {
                    ProgressView().controlSize(.mini)
                }
            }
    }
}

struct ResponseStatusBar: View {
    let response: PlexResponse

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let type = response.contentType.flatMap(Self.mediaType)
        let subtype = type.flatMap(Self.subtype(of:)).flatMap { $0 == type ? nil : $0 }
        let settles = !reduceMotion
        SheddingRow(spacing: 12, hasType: type != nil, hasSubtype: subtype != nil) {
            Text(String(response.status))
                .fontWeight(.semibold)
                .foregroundStyle(statusColor)
                .contentTransition(.numericText(value: Double(response.status)))
            Text(duration)
                .contentTransition(.numericText(value: Double(response.duration.milliseconds)))
            Text(size)
                .contentTransition(.numericText(value: Double(response.byteCount)))
            if let type {
                Text(type)
                    .contentTransition(.interpolate)
            }
            if let subtype {
                Text(subtype)
                    .contentTransition(.interpolate)
            }
        }
        .lineLimit(1)
        .clipped()
        .font(.code(.callout))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.fill.tertiary, in: .capsule)
        .keyframeAnimator(initialValue: 1.0, trigger: response.receivedAt) { view, scale in
            view.scaleEffect(settles ? scale : 1)
        } keyframes: { _ in
            KeyframeTrack {
                MoveKeyframe(0.97)
                SpringKeyframe(1.0, duration: 0.35, spring: .bouncy)
                MoveKeyframe(1.0)
            }
        }
        .help(summary.joined(separator: " · "))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.joined(separator: ", "))
        .animation(reduceMotion ? nil : .snappy, value: response.receivedAt)
        .layoutPriority(1)
    }

    private var duration: String {
        response.duration.formatted(.units(allowed: [.seconds, .milliseconds], width: .narrow))
    }

    private var size: String {
        response.byteCount.formatted(.byteCount(style: .file))
    }

    private var summary: [String] {
        [String(response.status), duration, size] + [response.contentType].compactMap(\.self)
    }

    private var statusColor: Color {
        switch response.status {
        case 200..<300: .green
        case 300..<400: .orange
        default: .red
        }
    }

    nonisolated static func mediaType(_ contentType: String) -> String? {
        let type = contentType.prefix { $0 != ";" }.trimmingCharacters(in: .whitespaces)
        return type.isEmpty ? nil : type
    }

    nonisolated static func subtype(of contentType: String) -> String? {
        guard let type = mediaType(contentType), let slash = type.firstIndex(of: "/") else { return nil }
        let token = type[type.index(after: slash)...].split(separator: "+").last.map(String.init)
        return token?.isEmpty == false ? token : nil
    }
}

/// A shed segment is placed outside the clipped bounds, not removed, so it stays the same view and its
/// number rolls; `ViewThatFits` draws the same choice without content transitions.
private struct SheddingRow: Layout {
    let spacing: CGFloat
    let hasType: Bool
    let hasSubtype: Bool

    private var levels: [[Int]] {
        var levels = [hasType ? [0, 1, 2, 3] : [0, 1, 2]]
        if hasSubtype { levels.append([0, 1, 2, 4]) }
        levels.append([0, 1, 2])
        levels.append([0])
        return levels
    }

    private func width(of indices: [Int], _ sizes: [CGSize]) -> CGFloat {
        indices.reduce(0) { $0 + sizes[$1].width } + spacing * CGFloat(max(indices.count - 1, 0))
    }

    /// Decided from the proposal in both passes: the placed bounds can come
    /// out a fraction narrower than the width measured for them.
    private func shown(for proposal: ProposedViewSize, _ sizes: [CGSize]) -> [Int] {
        let available = proposal.width ?? .infinity
        return levels.first { width(of: $0, sizes) <= available } ?? [0]
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let indices = shown(for: proposal, sizes)
        return CGSize(width: width(of: indices, sizes), height: indices.map { sizes[$0].height }.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let indices = shown(for: proposal, sizes)
        var x = bounds.minX
        for index in subviews.indices {
            guard indices.contains(index) else {
                subviews[index].place(at: CGPoint(x: bounds.maxX + 10_000, y: bounds.midY), anchor: .leading, proposal: .unspecified)
                continue
            }
            subviews[index].place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: .unspecified)
            x += sizes[index].width + spacing
        }
    }
}
