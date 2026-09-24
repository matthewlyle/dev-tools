import SwiftUI

/// The request's own actions (its documentation, copy from it, save it) as
/// toolbar items. On a regular width they're declared once over the detail,
/// with stable ids, so moving between the sections that show a request
/// leaves them where they are; a compact width's pushed request screen owns
/// its bar, so each screen declares them there. They're declared outside the
/// request block, which on the Response tab is hosted inside the text view,
/// out of reach of the toolbar.
struct RequestToolbarItems: ToolbarContent {
    let server: ConnectedServer?

    var body: some ToolbarContent {
        ToolbarItem(id: "request.documentation", placement: .primaryAction) {
            DocumentationButton()
        }
        ToolbarItem(id: "request.copy", placement: .primaryAction) {
            CopyMenu(server: server)
        }
        ToolbarItem(id: "request.save", placement: .primaryAction) {
            SaveButton(server: server)
        }
    }
}

private struct DocumentationButton: View {
    @Environment(RequestStore.self) private var requests
    @Environment(SpecStore.self) private var spec

    var body: some View {
        @Bindable var requests = requests
        let operation = spec.operation(matching: requests.current.path)
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
}

private struct CopyMenu: View {
    let server: ConnectedServer?

    @Environment(RequestStore.self) private var requests

    var body: some View {
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

/// Presents through the visible bar's save sheet, the same path as Save
/// Request… (⌘S).
private struct SaveButton: View {
    let server: ConnectedServer?

    @Environment(RequestStore.self) private var requests
    @Environment(SavedStore.self) private var saved

    var body: some View {
        let editing = requests.editingSavedID.flatMap { id in saved.saved.first { $0.id == id } }
        Button {
            requests.requestSave()
        } label: {
            Label(
                editing == nil ? "Save Request" : "Update Saved Request",
                systemImage: editing == nil ? "bookmark" : "bookmark.fill"
            )
        }
        .disabled(server == nil)
        .help(editing.map { "Editing “\($0.name)”: update it or save as new (⌘S)" } ?? "Save this request (⌘S)")
    }
}

/// A request screen's share of the request actions: the Show Documentation
/// command wherever it's the visible section, and on a compact width the
/// toolbar items for its own bar. On a regular width the detail declares
/// the items, so the screen adds no toolbar there at all.
private struct RequestScreenActions: ViewModifier {
    let server: ConnectedServer?

    @Environment(RequestStore.self) private var requests
    @Environment(SpecStore.self) private var spec
    @Environment(\.sectionIsActive) private var isActive
    @Environment(\.isCompactWidth) private var compact

    func body(content: Content) -> some View {
        let documented = spec.operation(matching: requests.current.path) != nil
        Group {
            if compact {
                content.sectionListToolbar(followsList: false) {
                    RequestToolbarItems(server: server)
                }
            } else {
                content
            }
        }
        .focusedSceneValue(
            \.showDocumentation,
            isActive && documented ? ShowDocumentationAction(path: requests.current.path) { requests.showingDocs = true } : nil
        )
    }
}

extension View {
    func requestScreenActions(server: ConnectedServer?) -> some View {
        modifier(RequestScreenActions(server: server))
    }
}
