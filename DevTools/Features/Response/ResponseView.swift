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
        Group {
            if let response = requests.response {
                switch tab {
                case .raw:
                    if let document = requests.document {
                        RawResponseView(document: document, response: response, collapsed: $collapsed) {
                            headerBlock
                        }
                    } else {
                        FillingScrollView {
                            headerBlock
                            ProgressView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                case .headers:
                    HeadersView(response: response, server: server, editable: editable) {
                        headerBlock
                    }
                }
            } else {
                FillingScrollView {
                    headerBlock
                    Group {
                        if let error = requests.errorMessage {
                            ContentUnavailableView(
                                "Request Failed",
                                systemImage: "exclamationmark.triangle",
                                description: Text(error)
                            )
                        } else {
                            ContentUnavailableView(
                                "No Response",
                                systemImage: "paperplane",
                                description: Text("Send a request to see the response here.")
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: requests.response?.receivedAt) { _, _ in
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
                HStack(spacing: 10) {
                    ResponseStatusBar(response: response)
                    if let pagination = requests.pagination {
                        PaginationControls(pagination: pagination, server: server)
                    }
                    if tab == .raw, let notice = requests.document?.notice {
                        Text(notice)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    Picker("View", selection: $tab) {
                        ForEach(ResponseTab.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    if tab == .raw, let response = requests.response, let document = requests.document {
                        BodyControls(document: document, response: response, collapsed: $collapsed)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .background(.fill.quaternary, in: .rect(cornerRadius: 12))
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
/// same at rest.
struct FillingScrollView<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    content()
                }
                .frame(minHeight: proxy.size.height)
            }
        }
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

struct PaginationControls: View {
    let pagination: PaginationInfo
    let server: ConnectedServer?

    @Environment(RequestStore.self) private var requests
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            Button {
                guard let server else { return }
                requests.page(start: pagination.start - pagination.pageSize, size: pagination.pageSize, on: server)
            } label: {
                Label("Previous Page", systemImage: "chevron.left")
                    .labelStyle(.iconOnly)
            }
            .disabled(!pagination.hasPrevious || server == nil)
            .help("Previous page")

            Text(pagination.label)
                .font(.code(.callout))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText(value: Double(pagination.start)))
                .help("Paged response: X-Plex-Container-Start / Total-Size")

            Button {
                guard let server else { return }
                requests.page(start: pagination.end, size: pagination.pageSize, on: server)
            } label: {
                Label("Next Page", systemImage: "chevron.right")
                    .labelStyle(.iconOnly)
            }
            .disabled(!pagination.hasNext || server == nil)
            .help("Next page")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        // Content layer, not chrome: a standard fill, not Liquid Glass.
        .background(.fill.tertiary, in: .capsule)
        .animation(reduceMotion ? nil : .snappy, value: pagination.start)
    }
}

struct ResponseStatusBar: View {
    let response: PlexResponse

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Digits roll in the direction the value moved whenever a new response
    /// lands; under Reduce Motion they simply change.
    var body: some View {
        HStack(spacing: 12) {
            Text(String(response.status))
                .fontWeight(.semibold)
                .foregroundStyle(statusColor)
                .contentTransition(.numericText(value: Double(response.status)))
            Text(response.duration.formatted(.units(allowed: [.seconds, .milliseconds], width: .narrow)))
                .contentTransition(.numericText(value: Double(response.duration.milliseconds)))
            Text(response.byteCount.formatted(.byteCount(style: .file)))
                .contentTransition(.numericText(value: Double(response.byteCount)))
            if let type = shortContentType {
                Text(type)
                    .contentTransition(.interpolate)
            }
        }
        .font(.code(.callout))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        // Content layer, not chrome: a standard fill, not Liquid Glass.
        .background(.fill.tertiary, in: .capsule)
        .animation(reduceMotion ? nil : .snappy, value: response.receivedAt)
    }

    private var statusColor: Color {
        switch response.status {
        case 200..<300: .green
        case 300..<400: .orange
        default: .red
        }
    }

    private var shortContentType: String? {
        response.contentType?.split(separator: ";").first.map(String.init)
    }
}
