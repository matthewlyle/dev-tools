import SwiftUI

@main
struct DevToolsApp: App {
    @State private var account: AccountStore
    @State private var servers: ServerStore
    @State private var requests: RequestStore
    @State private var spec = SpecStore()
    @State private var activity: ActivityStore
    @State private var saved: SavedStore

    init() {
        let identity = ClientIdentity.current()
        let plexTV = PlexTVClient(identity: identity)
        let http = PlexHTTP(identity: identity)
        _account = State(initialValue: AccountStore(plexTV: plexTV))
        _servers = State(initialValue: ServerStore(plexTV: plexTV, prober: ConnectionProber(http: http)))
        _requests = State(initialValue: RequestStore(http: http))
        _activity = State(initialValue: ActivityStore(identity: identity))
        _saved = State(initialValue: SavedStore())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(account)
                .environment(servers)
                .environment(requests)
                .environment(spec)
                .environment(activity)
                .environment(saved)
                .task { await spec.load() }
        }
        .defaultSize(width: 1400, height: 860)
        .commands {
            AppCommands(account: account, servers: servers, requests: requests, spec: spec)
        }

        Settings {
            SettingsView()
                .environment(requests)
        }
    }
}
