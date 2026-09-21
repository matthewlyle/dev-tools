import SwiftUI

/// Back/forward plus a breadcrumb trail of the current path. Each crumb is a
/// prefix of the path and opens it.
struct NavigationBar: View {
    let server: ConnectedServer?

    @Environment(RequestStore.self) private var requests

    private struct Crumb: Identifiable {
        let id: Int
        let label: String
        let path: String
    }

    private var crumbs: [Crumb] {
        let path = PlexRequest.splitPath(requests.current.path).path
        let segments = path.split(separator: "/", omittingEmptySubsequences: true)
        var result = [Crumb(id: 0, label: "/", path: "/")]
        var running = ""
        for (index, segment) in segments.enumerated() {
            running += "/" + segment
            result.append(Crumb(id: index + 1, label: String(segment), path: running))
        }
        return result
    }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                guard let server else { return }
                requests.goBack(on: server)
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .labelStyle(.iconOnly)
            }
            .disabled(!requests.canGoBack || server == nil)
            .help("Back (⌘[)")

            Button {
                guard let server else { return }
                requests.goForward(on: server)
            } label: {
                Label("Forward", systemImage: "chevron.right")
                    .labelStyle(.iconOnly)
            }
            .disabled(!requests.canGoForward || server == nil)
            .help("Forward (⌘])")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(crumbs) { crumb in
                        if crumb.id > 0 {
                            Image(systemName: "chevron.compact.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        Button(crumb.label) {
                            guard let server else { return }
                            requests.open(path: crumb.path, on: server)
                        }
                        .buttonStyle(.plain)
                        .font(.code(.callout))
                        .foregroundStyle(crumb.id == crumbs.count - 1 ? .primary : .secondary)
                        .disabled(server == nil)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
