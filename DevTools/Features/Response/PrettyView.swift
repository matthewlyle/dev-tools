import SwiftUI

struct PrettyView: View {
    let document: ResponseDocument
    let response: PlexResponse
    let server: ConnectedServer?

    @Environment(RequestStore.self) private var requests

    var body: some View {
        if document.format == .image {
            imageBody
        } else if let root = document.tree {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(root.name)
                            .font(.headline)
                        AttributeGrid(attributes: root.attributes, server: server)
                    }
                    .padding(.vertical, 4)
                }

                if !root.children.isEmpty {
                    Section("\(root.children.count) items") {
                        ForEach(root.children) { child in
                            NodeCard(node: child, server: server, basePath: requests.current.path)
                        }
                    }
                }
            }
            .listStyle(.inset)
        } else {
            ContentUnavailableView(
                "Not Structured",
                systemImage: "doc.plaintext",
                description: Text(document.notice ?? "This response isn't XML or JSON. See the Raw tab.")
            )
        }
    }

    @ViewBuilder
    private var imageBody: some View {
        if let image = NSImage(data: response.body) {
            ScrollView {
                VStack(spacing: 8) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 800, maxHeight: 800)
                        .clipShape(.rect(cornerRadius: 8))
                    Text("\(Int(image.size.width)) × \(Int(image.size.height))")
                        .font(.code(.caption))
                        .foregroundStyle(.secondary)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
        } else {
            ContentUnavailableView("Undecodable Image", systemImage: "photo")
        }
    }
}

/// One item: headline, badges, thumbnail, collapsible attributes, nested
/// elements grouped by name — and, when the item has a `key`, click-to-expand
/// that fetches the key in place and renders its items as nested cards.
struct NodeCard: View {
    let node: Node
    let server: ConnectedServer?
    /// Path the node came from; relative keys resolve against it.
    let basePath: String

    @Environment(RequestStore.self) private var requests
    @State private var showAttributes = false
    @State private var hovering = false

    @State private var expanded = false
    @State private var loading = false
    @State private var loadError: String?
    @State private var items: [Node] = []
    @State private var container: Node?
    @State private var total: Int?

    private static let pageSize = 100

    private struct Group: Identifiable {
        var id: String { name }
        let name: String
        let nodes: [Node]
    }

    private var groups: [Group] {
        var order: [String] = []
        var buckets: [String: [Node]] = [:]
        for child in node.children {
            if buckets[child.name] == nil { order.append(child.name) }
            buckets[child.name, default: []].append(child)
        }
        return order.map { Group(name: $0, nodes: buckets[$0]!) }
    }

    private var thumbnailValue: String? {
        for key in ["thumb", "parentThumb", "grandparentThumb", "composite"] {
            if let value = node[key], !value.isEmpty { return value }
        }
        return nil
    }

    private var keyPath: String? {
        guard let key = node["key"],
              case .server(let path) = LinkDetector.resolve(key, relativeTo: basePath)
        else { return nil }
        return path
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                if let server, let thumbnailValue, let url = LinkDetector.imageURL(for: thumbnailValue, server: server, height: 144) {
                    expandable {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Color.secondary.opacity(0.15)
                        }
                        .frame(width: 48, height: 72)
                        .clipShape(.rect(cornerRadius: 6))
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        if keyPath != nil {
                            expandable {
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(hovering || expanded ? .secondary : .tertiary)
                                    .rotationEffect(.degrees(expanded ? 90 : 0))
                                    .frame(width: 12)
                            }
                        }
                        expandable {
                            Text(node.headline)
                                .font(.headline)
                                .lineLimit(1)
                                .underline(hovering && keyPath != nil)
                        }
                        if let type = node["type"], !type.isEmpty {
                            badge(type)
                        }
                        if node.name != node.headline {
                            Text(node.name)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: 0)
                        if loading {
                            ProgressView().controlSize(.mini)
                        }
                    }

                    if let summary = node["summary"], !summary.isEmpty {
                        Text(summary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    DisclosureGroup(isExpanded: $showAttributes) {
                        AttributeGrid(attributes: node.attributes, server: server, basePath: basePath)
                            .padding(.top, 4)
                    } label: {
                        Text("\(node.attributes.count) attributes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(groups) { group in
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(group.nodes) { child in
                                    NodeCard(node: child, server: server, basePath: basePath)
                                        .padding(8)
                                        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 8))
                                }
                            }
                            .padding(.top, 4)
                        } label: {
                            HStack(spacing: 6) {
                                Text(group.name)
                                    .font(.caption.weight(.medium))
                                countBadge(group.nodes.count)
                            }
                        }
                    }
                }
            }

            if expanded {
                expansion
            }
        }
        .padding(.vertical, 4)
        .onHover { hovering = $0 }
    }

    // MARK: Expansion

    @ViewBuilder
    private var expansion: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let loadError {
                Label(loadError, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
            } else if !loading || !items.isEmpty {
                HStack(spacing: 6) {
                    if let keyPath {
                        Text(keyPath)
                            .font(.code(.caption))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    if let total {
                        Text("\(items.count.formatted()) of \(total.formatted())")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if items.isEmpty, let container {
                    if container.attributes.isEmpty {
                        Text("Empty")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        AttributeGrid(attributes: container.attributes, server: server, basePath: keyPath ?? basePath)
                    }
                }

                ForEach(items) { item in
                    NodeCard(node: item, server: server, basePath: keyPath ?? basePath)
                }

                if let total, items.count < total {
                    Button {
                        Task { await load(start: items.count) }
                    } label: {
                        Label("Load \(min(Self.pageSize, total - items.count)) more", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .disabled(loading)
                }
            }
        }
        .padding(.leading, 14)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(.quaternary)
                .frame(width: 2)
                .padding(.vertical, 2)
        }
    }

    private func toggle() {
        expanded.toggle()
        if expanded, items.isEmpty, container == nil, loadError == nil {
            Task { await load(start: 0) }
        }
    }

    private func load(start: Int) async {
        guard let server, let keyPath else { return }
        loading = true
        loadError = nil
        defer { loading = false }
        do {
            let peek = try await requests.peek(path: keyPath, on: server, start: start, size: Self.pageSize)
            guard let root = peek.document.tree else {
                loadError = "Not a structured response"
                return
            }
            container = root
            if start == 0 { items = root.children } else { items += root.children }
            total = peek.pagination?.total ?? items.count
        } catch {
            loadError = (error as? URLError)?.shortDescription ?? error.localizedDescription
        }
    }

    /// Wraps `content` in a click-to-expand button when the node has a
    /// server `key`; otherwise renders it plainly.
    @ViewBuilder
    private func expandable<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if let keyPath {
            Button(action: toggle) {
                content()
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(server == nil)
            .pointerStyle(.link)
            .help(expanded ? "Collapse" : "Expand \(keyPath)")
        } else {
            content()
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.tint.opacity(0.15), in: .capsule)
            .foregroundStyle(.tint)
    }

    private func countBadge(_ count: Int) -> some View {
        Text(String(count))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.quaternary, in: .capsule)
    }
}
