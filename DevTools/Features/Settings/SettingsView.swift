import SwiftUI

struct SettingsView: View {
    @Environment(RequestStore.self) private var requests
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("rawWrapLines") private var wrapLines = true
    @State private var confirmingClear = false

    var body: some View {
        #if os(macOS)
        TabView {
            Tab("General", systemImage: "gearshape") {
                general
            }
        }
        .scenePadding()
        .frame(width: 480)
        #else
        NavigationStack {
            general
                .navigationTitle("Settings")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        #endif
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
                Toggle("Wrap long lines in the Response view", isOn: $wrapLines)
            } header: {
                Text("Requests")
            }

            Section {
                LabeledContent("Recorded requests") {
                    Text(requests.history.count.formatted())
                        .contentTransition(.numericText(value: Double(requests.history.count)))
                        .animation(reduceMotion ? nil : .snappy, value: requests.history.count)
                }
                Button("Clear All History…", role: .destructive) {
                    confirmingClear = true
                }
                .disabled(requests.history.isEmpty)
                Text("Removes every recorded request across all servers. Saved requests are kept.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("History")
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Clear all \(requests.history.count.formatted()) recorded requests across every server?",
            isPresented: $confirmingClear,
            titleVisibility: .visible
        ) {
            Button("Clear All History", role: .destructive) {
                requests.clearHistory { _ in true }
            }
        } message: {
            Text("This can't be undone. Saved requests are kept.")
        }
    }
}
