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
            AppCommands(account: account, servers: servers, requests: requests)
        }

        Settings {
            SettingsView()
                .environment(requests)
                .environment(activity)
        }
    }
}
