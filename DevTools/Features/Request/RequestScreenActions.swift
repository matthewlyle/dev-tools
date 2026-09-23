import SwiftUI

/// The request's own actions — its documentation, copy from it, save it —
/// as toolbar items over the request: the pushed request screen's bar on a
/// compact width, the trailing end of the bar over the detail elsewhere,
/// where apps keep actions on the document being shown. The request block
/// keeps editing and sending. Declared on the screen, not the block: on the
/// Response tab the block is hosted inside the text view, out of reach of
/// the toolbar. Shown only while the section is, since sections stay mounted.
private struct RequestScreenActions: ViewModifier {
    let server: ConnectedServer?
    let showsDocs: Bool

    @Environment(RequestStore.self) private var requests
    @Environment(SavedStore.self) private var saved
    @Environment(SpecStore.self) private var spec
    @Environment(\.sectionIsActive) private var isActive

    private var editingSaved: SavedRequest? {
        requests.editingSavedID.flatMap { id in saved.saved.first { $0.id == id } }
    }

    func body(content: Content) -> some View {
        @Bindable var requests = requests
        let operation = showsDocs ? spec.operation(matching: requests.current.path) : nil
        return content.sectionListToolbar(followsList: false) {
            ToolbarItemGroup(placement: .primaryAction) {
                if showsDocs {
                    Button {
                        requests.showingDocs = true
                    } label: {
                        Label("Documentation", systemImage: "info.circle")
                    }
                    .disabled(operation == nil)
                    .help(operation?.summary ?? "No documentation for this path")
                    .popover(isPresented: $requests.showingDocs, arrowEdge: .bottom) {
                        if let operation { OperationDocs(operation: operation) }
                    }
                }
                copyMenu
                // Presents through the visible bar's save sheet, the same
                // path as Save Request… (⌘S).
                Button {
                    requests.requestSave()
                } label: {
                    Label(
                        editingSaved == nil ? "Save Request" : "Update Saved Request",
                        systemImage: editingSaved == nil ? "bookmark" : "bookmark.fill"
                    )
                }
                .disabled(server == nil)
                .help(editingSaved.map { "Editing “\($0.name)” — update it or save as new (⌘S)" } ?? "Save this request (⌘S)")
            }
        }
        .focusedSceneValue(
            \.showDocumentation,
            isActive && operation != nil ? ShowDocumentationAction(path: requests.current.path) { requests.showingDocs = true } : nil
        )
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
        .help("Copy the response body, URL, or cURL command")
    }
}

extension View {
    /// `showsDocs` where the screen presents the request's documentation.
    func requestScreenActions(server: ConnectedServer?, showsDocs: Bool = false) -> some View {
        modifier(RequestScreenActions(server: server, showsDocs: showsDocs))
    }
}
