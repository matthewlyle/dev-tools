import SwiftUI

/// Renders one attribute value: a navigable button for server paths, a
/// `Link` for external URLs, else text with a friendlier form when known.
struct AttributeValueView: View {
    let attribute: Attribute
    let server: ConnectedServer?
    /// Request path relative keys resolve against; defaults to the address bar.
    var basePath: String? = nil

    @Environment(RequestStore.self) private var requests

    var body: some View {
        // Credentials are shown masked and can't be copied out, by design.
        if requests.shouldMask(attributeNamed: attribute.name), !attribute.value.isEmpty {
            Text(RequestStore.mask)
                .font(.code(.callout))
                .foregroundStyle(.secondary)
                .help("Credential — never shown")
        } else if LinkDetector.isNavigable(attribute),
           let link = LinkDetector.resolve(attribute.value, relativeTo: basePath ?? requests.current.path) {
            switch link {
            case .server(let path):
                Button(attribute.value) {
                    guard let server else { return }
                    requests.open(path: path, on: server)
                }
                .buttonStyle(.link)
                .font(.code(.callout))
                .disabled(server == nil)
                .help(path)
                .contextMenu {
                    Button("Copy Path") { copy(path) }
                }
            case .external(let url):
                Link(attribute.value, destination: url)
                    .font(.code(.callout))
                    .contextMenu {
                        Button("Copy URL") { copy(url.absoluteString) }
                    }
            }
        } else if let display = ValueFormatter.display(attribute) {
            Text(display)
                .font(.callout)
                .help(attribute.value)
                .contextMenu {
                    Button("Copy Raw Value") { copy(attribute.value) }
                }
        } else {
            Text(attribute.value)
                .font(.code(.callout))
                .textSelection(.enabled)
                .lineLimit(4)
        }
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

/// Two-column name/value grid for a node's attributes.
struct AttributeGrid: View {
    let attributes: [Attribute]
    let server: ConnectedServer?
    var basePath: String? = nil

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 4) {
            ForEach(attributes) { attribute in
                GridRow {
                    Text(attribute.name)
                        .font(.code(.caption))
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    AttributeValueView(attribute: attribute, server: server, basePath: basePath)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
