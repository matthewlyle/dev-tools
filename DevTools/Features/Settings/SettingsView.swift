import SwiftUI

/// ⌘, — one home for defaults that used to be scattered across menus and
/// view chrome. Tabbed from day one so new groups have somewhere to go.
struct SettingsView: View {
    @Environment(RequestStore.self) private var requests
    @Environment(ActivityStore.self) private var activity
    @AppStorage("rawWrapLines") private var wrapLines = true

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                general
            }
        }
        .scenePadding()
        .frame(width: 480)
    }

    private var general: some View {
        @Bindable var requests = requests
        @Bindable var activity = activity

        return Form {
            Section {
                Toggle("Redact tokens", isOn: $requests.redactToken)
                Text("Masks X-Plex-Token in URLs, copies, history, and token-like response values. Toggle from the request bar or with ⇧⌘R.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Privacy")
            }

            Section("Responses") {
                Toggle("Wrap long lines in the Raw view", isOn: $wrapLines)
            }

            Section {
                Picker("Transport", selection: $activity.transport) {
                    ForEach(ActivityTransport.allCases) { Text($0.rawValue).tag($0) }
                }
                .disabled(activity.status.isActive)
                Text("WebSocket is the server's primary feed. EventSource is plain HTTP, for connections that can't upgrade.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Activity")
            }
        }
        .formStyle(.grouped)
    }
}
