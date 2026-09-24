import SwiftUI

struct HistoryNavButtons: View {
    let server: ConnectedServer?

    @Environment(RequestStore.self) private var requests

    var body: some View {
        HStack(spacing: 2) {
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
        }
        .buttonStyle(.borderless)
    }
}
