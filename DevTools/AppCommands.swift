import SwiftUI

/// Published by the History section while it has something to clear;
/// absent → the menu command is disabled. Equatable by scope so the menu
/// isn't invalidated every time the list re-renders.
struct ClearHistoryAction: Equatable {
    let serverID: String
    let run: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.serverID == rhs.serverID }
}

extension FocusedValues {
    @Entry var clearHistory: ClearHistoryAction?
}

/// Menu bar. Every toolbar item has a command here — toolbars are
/// customizable and hideable, so they can't be a command's only home.
struct AppCommands: Commands {
    let account: AccountStore
    let servers: ServerStore
    let requests: RequestStore

    @AppStorage("serverSection") private var section: ServerSection = .endpoints
    @AppStorage("rawWrapLines") private var wrapLines = true
    @FocusedValue(\.clearHistory) private var clearHistory

    private var activeServer: ConnectedServer? {
        servers.selected.flatMap { servers.connectedServer(for: $0) }
    }

    var body: some Commands {
        // View menu: which section of the server is showing, and display toggles.
        CommandGroup(after: .sidebar) {
            Divider()
            Picker("Section", selection: $section) {
                Text("Endpoints").tag(ServerSection.endpoints)
                    .keyboardShortcut("1", modifiers: .command)
                Text("History").tag(ServerSection.history)
                    .keyboardShortcut("2", modifiers: .command)
                Text("Activity").tag(ServerSection.activity)
                    .keyboardShortcut("3", modifiers: .command)
            }
            .pickerStyle(.inline)
            .disabled(servers.selected == nil)
        }

        CommandGroup(after: .toolbar) {
            Toggle("Wrap Lines", isOn: $wrapLines)
        }

        CommandMenu("Server") {
            Button("Refresh Servers") {
                guard let token = account.token else { return }
                Task { await servers.refresh(token: token) }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(account.token == nil || servers.isRefreshing)

            Button("Probe Connections") {
                guard let id = servers.selectedID else { return }
                Task { await servers.probe(id: id) }
            }
            .disabled(servers.selected == nil || servers.selected?.isProbing == true)

            Divider()

            Button("Clear History…") { clearHistory?.run() }
                .disabled(clearHistory == nil)
        }

        CommandMenu("Request") {
            Button("Send") {
                guard let server = activeServer else { return }
                requests.send(to: server)
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(activeServer == nil || account.user == nil)

            Button("Cancel Request") { requests.cancel() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!requests.isSending)

            Divider()

            Button("Focus Path") { requests.requestPathFocus() }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(account.user == nil)

            Divider()

            Button("Back") {
                guard let server = activeServer else { return }
                requests.goBack(on: server)
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(activeServer == nil || !requests.canGoBack)

            Button("Forward") {
                guard let server = activeServer else { return }
                requests.goForward(on: server)
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(activeServer == nil || !requests.canGoForward)
        }
    }
}
