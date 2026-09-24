import SwiftUI

@main
struct DevToolsApp: App {
    @State private var account: AccountStore
    @State private var servers: ServerStore
    @State private var requests: RequestStore
    @State private var spec = SpecStore()
    @State private var activity: ActivityStore
    @State private var saved: SavedStore
    @State private var memory: ValueMemory
    @State private var mediaQuery: MediaQueryStore
    @State private var images: ImageStore
    @State private var lightbox = LightboxStore()

    init() {
        let identity = ClientIdentity.current()
        let plexTV = PlexTVClient(identity: identity)
        let http = PlexHTTP(identity: identity)
        _account = State(initialValue: AccountStore(plexTV: plexTV))
        _servers = State(initialValue: ServerStore(plexTV: plexTV, prober: ConnectionProber(http: http)))
        let memory = ValueMemory()
        _memory = State(initialValue: memory)
        _requests = State(initialValue: RequestStore(http: http, memory: memory))
        _activity = State(initialValue: ActivityStore(http: http))
        _saved = State(initialValue: SavedStore())
        _mediaQuery = State(initialValue: MediaQueryStore(http: http))
        _images = State(initialValue: ImageStore(http: http))
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
                .environment(memory)
                .environment(mediaQuery)
                .environment(images)
                .environment(lightbox)
                .task { await spec.load() }
        }
        .defaultSize(width: 1400, height: 860)
        .commands {
            AppCommands(account: account, servers: servers, requests: requests, spec: spec)
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(requests)
                .environment(account)
                .environment(servers)
                .environment(images)
                .environment(activity)
                .environment(mediaQuery)
        }
        #endif
    }
}
