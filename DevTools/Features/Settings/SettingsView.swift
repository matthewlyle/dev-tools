import SwiftUI

struct SettingsView: View {
    @Environment(RequestStore.self) private var requests
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("rawWrapLines") private var wrapLines = true
    #if os(macOS)
    @AppStorage("translucentBackground") private var translucent = true
    #endif
    @AppStorage(CodeTheme.storageKey) private var codeTheme: CodeTheme = .system
    #if os(iOS)
    @AppStorage(WashStyle.storageKey) private var wash: WashStyle = .indigoTeal
    #endif
    @State private var confirmingClear = false
    @State private var confirmingSignOut = false

    var body: some View {
        #if os(macOS)
        general
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
            if let user = account.user {
                Section {
                    HStack(spacing: 12) {
                        AsyncImage(url: user.thumbURL) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 36, height: 36)
                        .clipShape(.circle)
                        .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.title)
                            Text(user.username)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button("Sign Out…", role: .destructive) {
                        confirmingSignOut = true
                    }
                } header: {
                    Text("Account")
                }
            }

            Section {
                Picker("Response format", selection: $requests.acceptFormat) {
                    ForEach(AcceptFormat.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Wrap long lines in the Response view", isOn: $wrapLines)
            } header: {
                Text("Requests")
            }

            Section {
                Picker("Code theme", selection: $codeTheme) {
                    ForEach(CodeTheme.allCases) { Text($0.title).tag($0) }
                }
                #if os(macOS)
                Toggle("Translucent background", isOn: $translucent)
                #else
                Picker("Background", selection: $wash) {
                    ForEach(WashStyle.allCases) { Text($0.title).tag($0) }
                }
                #endif
            } header: {
                Text("Appearance")
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
            } header: {
                Text("History")
            }
        }
        .formStyle(.grouped)
        .signOutConfirmation(isPresented: $confirmingSignOut) { dismiss() }
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
