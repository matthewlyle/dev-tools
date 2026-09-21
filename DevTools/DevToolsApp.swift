import SwiftUI

@main
struct DevToolsApp: App {
    @State private var account: AccountStore
    @State private var servers: ServerStore
    @State private var requests: RequestStore
    @State private var spec = SpecStore()
    @State private var activity: ActivityStore

    init() {
        let identity = ClientIdentity.current()
        let plexTV = PlexTVClient(identity: identity)
        let http = PlexHTTP(identity: identity)
        _account = State(initialValue: AccountStore(plexTV: plexTV))
        _servers = State(initialValue: ServerStore(plexTV: plexTV, prober: ConnectionProber(http: http)))
        _requests = State(initialValue: RequestStore(http: http))
        _activity = State(initialValue: ActivityStore(identity: identity))
    }

    private var activeServer: ConnectedServer? {
        servers.selected.flatMap { servers.connectedServer(for: $0) }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(account)
                .environment(servers)
                .environment(requests)
                .environment(spec)
                .environment(activity)
                .task { await spec.load() }
        }
        .defaultSize(width: 1400, height: 860)

        WindowGroup("Activity", id: "activity") {
            ActivityWindowView()
                .environment(servers)
                .environment(activity)
        }
        .defaultSize(width: 1000, height: 640)
        .commands {
            CommandGroup(after: .toolbar) {
                Toggle("Redact Tokens", isOn: Binding(
                    get: { requests.redactToken },
                    set: { requests.redactToken = $0 }
                ))
                .keyboardShortcut("r", modifiers: [.command, .shift])
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
}
