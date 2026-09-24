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

    /// Documented query parameters for the current route when the server
    /// rejected the request — the spec often omits `required`, so a 400 is
    /// the first hint that one of these matters.
    private var missingParameterHint: [SpecParameter]? {
        guard let response = requests.response, response.status == 400,
              let operation = spec.operation(matching: requests.current.path)
        else { return nil }
        let present = Set(requests.current.query.filter(\.enabled).map { $0.name.lowercased() })
        let candidates = operation.queryParameters.filter { !present.contains($0.name.lowercased()) }
        return candidates.isEmpty ? nil : candidates
    }

    /// A 403 on an admin-only operation against a server you don't own has
    /// one explanation; say it rather than leave a bare status code.
    private var adminOnlyHint: SpecOperation? {
        guard let response = requests.response, response.status == 403, server?.owned == false,
              let operation = spec.operation(matching: requests.current.path), operation.access == .admin
        else { return nil }
        return operation
    }

    var body: some View {
        // Only the resting and error states transition; the body arrives
        // instantly because a transition on the text view forces a
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
                // Nothing picked from History: the bar would show the
                // workspace's placeholder request, and the list says what
                // belongs there.
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

    /// The request and everything that describes its response, as one block.
    /// Scrolls with the body where the body can host it (the text view, the
    /// poster grid); sits above it otherwise.
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

/// A scroll view whose content is at least the viewport tall. Static states
/// (empty, loading) go through it so the detail is always a scroll surface:
/// on macOS the toolbar draws its backdrop over static content and turns
/// transparent only over a scroll view, and every section should look the
/// same at rest. The content is pinned to the top: a scroll view proposes no
/// height, so while the viewport changes size (the keyboard rising) the
/// content can briefly be shorter than the minimum, and a centred frame
/// would float the request bar down the screen.
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

/// The detail's resting state: one muted sentence, centred. No icon or
/// heading — the section switcher already says where you are.
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
    /// How a resting, empty, or error state swaps with content: it arrives
    /// over a beat and leaves at once, so content never waits on it. `rising`
    /// adds a small lift on arrival, for states that don't carry the request
    /// bar — the bar must not move.
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

/// The status row under the request: status, paging, any notice, the body's
/// controls, and the view tabs. A compact width can't hold all of them on
/// one line, so the tabs share the first with the status and paging and any
/// notice drop to a second, shown only when it has something in it; copying
/// the body is in the screen's navigation bar there (`requestScreenActions`).
struct ResponseInfoRow<Tabs: View>: View {
    let response: PlexResponse
    let pagination: PaginationInfo?
    let server: ConnectedServer?
    var notice: String? = nil
    var controls: BodyControls? = nil
    @ViewBuilder let tabs: () -> Tabs

    @Environment(\.isCompactWidth) private var compact

    var body: some View {
        Group {
            if compact {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        ResponseStatusBar(response: response)
                        Spacer(minLength: 0)
                        tabs()
                    }
                    if pagination != nil || notice != nil {
                        HStack(spacing: 10) {
                            secondary
                        }
                    }
                }
            } else {
                HStack(spacing: 10) {
                    ResponseStatusBar(response: response)
                    secondary
                    tabs()
                }
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

struct PaginationControls: View {
    let pagination: PaginationInfo
    let server: ConnectedServer?

    @Environment(RequestStore.self) private var requests
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Action { case previous, next, all }
    /// The page being fetched, so its button shows the progress: Send's
    /// spinner is across the window from the button that was pressed.
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
        // Content layer, not chrome: a standard fill, not Liquid Glass.
        .background(.fill.tertiary, in: .capsule)
        .animation(reduceMotion ? nil : .snappy, value: pagination)
    }

    /// The pressed button stays enabled so its spinner isn't dimmed; a second
    /// press is ignored in `run` instead.
    private func unavailable(for action: Action) -> Bool {
        server == nil || (requests.isSending && pending != action)
    }

    private func run(_ action: Action, _ fetch: (ConnectedServer) -> Void) {
        guard let server, !requests.isSending else { return }
        pending = action
        fetch(server)
    }

    /// Swaps in a spinner at the content's own size, so nothing shifts.
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

/// Every segment is unsplittable: when the row runs short the pill sheds
/// detail — content type to its subtype, then gone, then the measurements —
/// rather than wrap. It outranks its row siblings for width so it only sheds
/// once the row is genuinely full.
struct ResponseStatusBar: View {
    let response: PlexResponse

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let type = response.contentType.flatMap(Self.mediaType)
        let settles = !reduceMotion
        ViewThatFits(in: .horizontal) {
            readout(type: type)
            if let type, let subtype = Self.subtype(of: type), subtype != type {
                readout(type: subtype)
            }
            if type != nil {
                readout(type: nil)
            }
            readout(type: nil, measurements: false)
        }
        .font(.code(.callout))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        // Content layer, not chrome: a standard fill, not Liquid Glass.
        .background(.fill.tertiary, in: .capsule)
        .keyframeAnimator(initialValue: 1.0, trigger: response.receivedAt) { view, scale in
            view.scaleEffect(settles ? scale : 1)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(0.97, duration: 0)
                SpringKeyframe(1.0, duration: 0.35, spring: .bouncy)
            }
        }
        .help(summary.joined(separator: " · "))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.joined(separator: ", "))
        .animation(reduceMotion ? nil : .snappy, value: response.receivedAt)
        .layoutPriority(1)
    }

    private func readout(type: String?, measurements: Bool = true) -> some View {
        HStack(spacing: 12) {
            Text(String(response.status))
                .fontWeight(.semibold)
                .foregroundStyle(statusColor)
                .contentTransition(.numericText(value: Double(response.status)))
            if measurements {
                Text(duration)
                    .contentTransition(.numericText(value: Double(response.duration.milliseconds)))
                Text(size)
                    .contentTransition(.numericText(value: Double(response.byteCount)))
            }
            if let type {
                Text(type)
                    .contentTransition(.interpolate)
            }
        }
        .lineLimit(1)
        .fixedSize()
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

    /// `application/json` → `json`; a structured suffix wins, so
    /// `application/vnd.api+json` → `json`.
    nonisolated static func subtype(of contentType: String) -> String? {
        guard let type = mediaType(contentType), let slash = type.firstIndex(of: "/") else { return nil }
        let token = type[type.index(after: slash)...].split(separator: "+").last.map(String.init)
        return token?.isEmpty == false ? token : nil
    }
}
