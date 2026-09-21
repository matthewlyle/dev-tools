import SwiftUI

/// ⌘, — one home for defaults that used to be scattered across menus and
/// view chrome. Tabbed from day one so new groups have somewhere to go.
struct SettingsView: View {
    @Environment(RequestStore.self) private var requests
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

        return Form {
            Section {
                Picker("Response format", selection: $requests.acceptFormat) {
                    ForEach(AcceptFormat.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("Sent as the Accept header on every request. Plex answers XML unless JSON is asked for; new integrations should use JSON.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Toggle("Wrap long lines in the Raw view", isOn: $wrapLines)
            } header: {
                Text("Requests")
            }

            Section {
                Toggle("Redact tokens", isOn: $requests.redactToken)
                Text("Masks X-Plex-Token in URLs, copies, history, and token-like response values. Toggle from the request bar or with ⇧⌘R.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Privacy")
            }
        }
        .formStyle(.grouped)
    }
}
