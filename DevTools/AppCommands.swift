import SwiftUI

struct ClearHistoryAction: Equatable {
    let serverID: String
    let run: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.serverID == rhs.serverID }
}

/// Published by the Media Query builder while it can run; Send (⌘↩) runs the
/// built query instead of the request bar's request.
struct RunMediaQueryAction: Equatable {
    let summary: String
    let run: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.summary == rhs.summary }
}

/// Published by the History list while a row is selected.
struct DeleteHistoryEntryAction: Equatable {
    let id: HistoryEntry.ID
    let run: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

/// Published by the Media results grid while a poster is selected, and by the
/// Activity event list while an event is (its inspector only ever hides).
struct ShowMediaInfoAction: Equatable {
    let visible: Bool
    let run: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.visible == rhs.visible }
}

/// Published by the window header while a server is selected.
struct ShowServerInfoAction: Equatable {
    let run: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool { true }
}

#if os(iOS)
/// Published by the iPad window header. iPadOS has no Settings scene, so the
/// App menu's Settings… presents the header's sheet in the focused window.
struct ShowSettingsAction: Equatable {
    let run: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool { true }
}
#endif

extension FocusedValues {
    @Entry var clearHistory: ClearHistoryAction?
    @Entry var deleteHistoryEntry: DeleteHistoryEntryAction?
    @Entry var runMediaQuery: RunMediaQueryAction?
    @Entry var showMediaInfo: ShowMediaInfoAction?
    @Entry var showServerInfo: ShowServerInfoAction?
    #if os(iOS)
    @Entry var showSettings: ShowSettingsAction?
    #endif
}

struct AppCommands: Commands {
    let account: AccountStore
    let servers: ServerStore
    let requests: RequestStore
    let spec: SpecStore

    @AppStorage("rawWrapLines") private var wrapLines = true
    @FocusedValue(\.clearHistory) private var clearHistory
    @FocusedValue(\.deleteHistoryEntry) private var deleteHistoryEntry
    @FocusedValue(\.runMediaQuery) private var runMediaQuery
    @FocusedValue(\.showMediaInfo) private var showMediaInfo
    @FocusedValue(\.showServerInfo) private var showServerInfo
    #if os(iOS)
    @FocusedValue(\.showSettings) private var showSettings
    #endif
    @Environment(\.openURL) private var openURL

    private var activeServer: ConnectedServer? {
        servers.selected.flatMap { servers.connectedServer(for: $0) }
    }

    private var currentDocsURL: URL? {
        spec.operation(matching: requests.current.path)?.docsURL
    }

    var body: some Commands {
        #if os(iOS)
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { showSettings?.run() }
                .keyboardShortcut(",", modifiers: .command)
                .disabled(showSettings == nil)
        }
        #endif

        CommandGroup(after: .appSettings) {
            Button("Sign Out…") { account.isConfirmingSignOut = true }
                .disabled(account.user == nil)
        }

        CommandGroup(after: .toolbar) {
            Toggle("Wrap Lines", isOn: $wrapLines)
            Button(showMediaInfo?.visible == true ? "Hide Info" : "Show Info") { showMediaInfo?.run() }
                .keyboardShortcut("i", modifiers: .command)
                .disabled(showMediaInfo == nil)
        }

        CommandMenu("Server") {
            Picker("Server", selection: Binding(
                get: { servers.selectedID },
                set: { servers.selectedID = $0 }
            )) {
                ForEach(servers.sortedEntries) { entry in
                    Text(entry.resource.name).tag(Optional(entry.id))
                }
            }
            .pickerStyle(.inline)
            .disabled(servers.entries.isEmpty)

            Divider()

            Button("Show Server Info") { showServerInfo?.run() }
                .disabled(showServerInfo == nil)

            Button("Refresh Servers") {
                guard let token = account.token else { return }
                Task { await servers.refresh(token: token) }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(account.token == nil || servers.isRefreshing)

            Divider()

            Button("Delete History Item") { deleteHistoryEntry?.run() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(deleteHistoryEntry == nil)

            Button("Clear History…") { clearHistory?.run() }
                .disabled(clearHistory == nil)
        }

        CommandMenu("Request") {
            Button("Save Request…") { requests.requestSave() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(activeServer == nil)

            Button("Copy as cURL") {
                guard let server = activeServer, let command = requests.curl(for: server) else { return }
                Clipboard.copy(command)
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(activeServer == nil)

            Button("Open in Developer Docs") {
                if let url = currentDocsURL { openURL(url) }
            }
            .disabled(currentDocsURL == nil)

            Divider()

            Button("Send") {
                if let runMediaQuery {
                    runMediaQuery.run()
                } else if let server = activeServer {
                    requests.send(to: server)
                }
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
