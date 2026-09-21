import SwiftUI

/// An item's metadata, read top-down: title and one-line summary, tagline and
/// synopsis, tag groups as sentences, then every attribute with units
/// decoded, and nested elements collapsed. Artwork isn't repeated here — the
/// selected poster is already showing in the grid. `Image` elements render as
/// thumbnails that open in a lightbox; `UltraBlurColors` as a palette.
struct MediaInfoView: View {
    let item: MediaItem
    let server: ConnectedServer?
    let dismiss: () -> Void

    @Environment(RequestStore.self) private var requests

    /// Attributes already surfaced above the details grid.
    private static let surfaced: Set<String> = ["title", "summary", "tagline"]

    private var details: [Attribute] {
        item.node.attributes.filter { !Self.surfaced.contains($0.name) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.title)
                            .font(.title.weight(.semibold))
                            .textSelection(.enabled)
                        if let subtitle = item.subtitle {
                            Text(subtitle)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 12)
                    Button(action: dismiss) {
                        Label("Hide Info", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .help("Hide Info (⌘I)")
                }

                if item.tagline != nil || item.summary != nil {
                    VStack(alignment: .leading, spacing: 12) {
                        if let tagline = item.tagline {
                            Text(tagline)
                                .font(.body.italic())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        if let summary = item.summary {
                            Text(summary)
                                .font(.body)
                                .lineSpacing(5)
                                .textSelection(.enabled)
                        }
                    }
                }

                let tagGroups = item.tagGroups
                if !tagGroups.isEmpty {
                    Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 10) {
                        ForEach(tagGroups, id: \.name) { group in
                            GridRow {
                                Text(group.name)
                                    .foregroundStyle(.secondary)
                                    .gridColumnAlignment(.trailing)
                                Text(group.tags.joined(separator: ", "))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .font(.body)
                }

                Divider()

                VStack(alignment: .leading, spacing: 14) {
                    Text("Details")
                        .font(.title3.weight(.semibold))
                    AttributeTable(attributes: details, masking: requests.shouldMask(attributeNamed:))
                }

                ForEach(item.elementGroups, id: \.name) { group in
                    switch group.name {
                    case "Image":
                        ImageStrip(nodes: group.nodes, server: server)
                    case "UltraBlurColors":
                        Palette(nodes: group.nodes)
                    default:
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(group.nodes) { child in
                                    ElementDetail(node: child, masking: requests.shouldMask(attributeNamed:))
                                        .padding(10)
                                        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 8))
                                }
                            }
                            .padding(.top, 6)
                        } label: {
                            groupLabel(group.name, count: group.nodes.count)
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private func groupLabel(_ name: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(name)
                .font(.title3.weight(.semibold))
            Text(String(count))
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: .capsule)
        }
    }
}

/// Name → value rows. Names are secondary system text; values are primary,
/// decoded where the name gives away a unit, otherwise in the code face.
/// Credentials are masked and can't be copied.
private struct AttributeTable: View {
    let attributes: [Attribute]
    let masking: (String) -> Bool

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 10) {
            ForEach(attributes) { attribute in
                GridRow {
                    Text(attribute.name)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    value(for: attribute)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private func value(for attribute: Attribute) -> some View {
        if masking(attribute.name), !attribute.value.isEmpty {
            Text(RequestStore.mask)
                .font(.code(.body))
                .foregroundStyle(.secondary)
                .help("Credential — never shown")
        } else if let display = MediaValue.display(name: attribute.name, value: attribute.value) {
            Text(display)
                .font(.body)
                .help(attribute.value)
                .textSelection(.enabled)
        } else {
            Text(attribute.value)
                .font(.code(.body))
                .textSelection(.enabled)
                .lineLimit(4)
        }
    }
}

/// A nested element (Media, Part, Stream…) as its attributes plus its own
/// children, recursively.
private struct ElementDetail: View {
    let node: Node
    let masking: (String) -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !node.attributes.isEmpty {
                AttributeTable(attributes: node.attributes, masking: masking)
            }
            ForEach(node.children) { child in
                DisclosureGroup(child.name) {
                    ElementDetail(node: child, masking: masking)
                        .padding(.top, 6)
                }
                .font(.body)
            }
        }
    }
}

/// `Image` elements as thumbnails with their type underneath. Clicking one
/// opens it in the window lightbox, which grows the image out of the
/// thumbnail's frame.
private struct ImageStrip: View {
    let nodes: [Node]
    let server: ConnectedServer?

    @Environment(LightboxStore.self) private var lightbox

    static let thumbSize = CGSize(width: 130, height: 90)

    private var items: [LightboxItem] {
        nodes.compactMap { node in
            guard let url = node["url"], !url.isEmpty else { return nil }
            return LightboxItem(url: url, title: node["type"] ?? node["alt"] ?? "Image")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Image")
                    .font(.title3.weight(.semibold))
                Text(String(items.count))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: .capsule)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130, maximum: 160), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
                ForEach(items) { item in
                    Thumbnail(item: item, server: server) { frame in
                        guard let server else { return }
                        lightbox.open(item, on: server, from: frame)
                    }
                }
            }
        }
    }

    private struct Thumbnail: View {
        let item: LightboxItem
        let server: ConnectedServer?
        let open: (CGRect) -> Void

        @State private var frame: CGRect = .zero

        var body: some View {
            Button {
                open(frame)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    RemoteImage(value: item.url, server: server, size: ImageStrip.thumbSize, fit: true) {
                        Rectangle().fill(.quaternary)
                    }
                    .background(.quaternary.opacity(0.4))
                    .clipShape(.rect(cornerRadius: 8))
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
                    Text(item.title)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(item.url)
        }
    }
}

/// `UltraBlurColors` as swatches: the four corners Plex derives for its
/// blurred backgrounds, each with its hex.
private struct Palette: View {
    let nodes: [Node]

    private static let corners = ["topLeft", "topRight", "bottomLeft", "bottomRight"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("UltraBlur Colors")
                .font(.title3.weight(.semibold))
            ForEach(nodes) { node in
                HStack(spacing: 12) {
                    ForEach(Self.corners, id: \.self) { corner in
                        if let hex = node[corner], let color = Color(plexHex: hex) {
                            VStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(color)
                                    .frame(width: 56, height: 56)
                                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                                    .accessibilityLabel("\(corner) \(hex)")
                                Text(corner)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(hex)
                                    .font(.code(.caption))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
        }
    }
}

extension Color {
    /// Plex sends UltraBlur colours as bare `RRGGBB` hex.
    init?(plexHex: String) {
        let digits = plexHex.hasPrefix("#") ? String(plexHex.dropFirst()) : plexHex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
