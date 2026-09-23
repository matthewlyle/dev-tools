import SwiftUI

/// On a compact width the request screen is pushed, and its own actions —
/// its documentation, copy from it, save it — sit in its navigation bar
/// rather than scattered through the request block. Wider layouts keep them
/// in the block, beside what they act on, since there the screen shares one
/// bar with the list. Declared on the screen, not the block: on the Response
/// tab the block is hosted inside the text view, out of reach of the
/// navigation bar.
private struct RequestScreenActions: ViewModifier {
    let server: ConnectedServer?
    let showsDocs: Bool

    @Environment(RequestStore.self) private var requests
    @Environment(SavedStore.self) private var saved
    @Environment(SpecStore.self) private var spec
    @Environment(\.isCompactWidth) private var compact

    private var editingSaved: SavedRequest? {
        requests.editingSavedID.flatMap { id in saved.saved.first { $0.id == id } }
    }

    func body(content: Content) -> some View {
        if compact {
            content.toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if showsDocs {
                        // Presents from the response view, as the ⓘ beside
                        // the path does on wider layouts.
                        Button {
                            requests.showingDocs = true
                        } label: {
                            Label("Documentation", systemImage: "info.circle")
                        }
                        .disabled(spec.operation(matching: requests.current.path) == nil)
                    }
                    copyMenu
                    // Presents through the visible bar's save sheet, the
                    // same path as Save Request… (⌘S).
                    Button {
                        requests.requestSave()
                    } label: {
                        Label(
                            editingSaved == nil ? "Save Request" : "Update Saved Request",
                            systemImage: editingSaved == nil ? "bookmark" : "bookmark.fill"
                        )
                    }
                    .disabled(server == nil)
                }
            }
        } else {
            content
        }
    }

    private var copyMenu: some View {
        Menu {
            if let document = requests.document, let response = requests.response {
                Button(document.format == .image ? "Copy Response Image" : "Copy Response Body") {
                    BodyControls.copy(document: document, response: response)
                }
            }
            Button("Copy URL") {
                if let server, let url = requests.shareableURL(for: server) { Clipboard.copy(url) }
            }
            Button("Copy as cURL") {
                if let server, let command = requests.curl(for: server) { Clipboard.copy(command) }
            }
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        .disabled(server == nil)
    }
}

extension View {
    /// `showsDocs` where the screen presents the request's documentation.
    func requestScreenActions(server: ConnectedServer?, showsDocs: Bool = false) -> some View {
        modifier(RequestScreenActions(server: server, showsDocs: showsDocs))
    }
}
