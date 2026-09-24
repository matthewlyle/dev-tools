import SwiftUI

struct SettingsView: View {
    @Environment(RequestStore.self) private var requests
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @AppStorage("rawWrapLines") private var wrapLines = true
    #if os(macOS)
    @AppStorage("translucentBackground") private var translucent = true
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
                        AccountAvatar(url: user.thumbURL, side: 36)
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
                Toggle("Wrap long lines", isOn: $wrapLines)
            } header: {
                Text("Requests")
            }

            #if os(macOS)
            Section {
                Toggle("Translucent background", isOn: $translucent)
            } header: {
                Text("Appearance")
            }
            #endif

            Section {
                Button("Clear All History…", role: .destructive) {
                    confirmingClear = true
                }
                .disabled(requests.history.isEmpty)
            } header: {
                Text("History")
            }
        }
        .formStyle(.grouped)
        .signOutConfirmation(isPresented: $confirmingSignOut)
        .platformClosesWindow(when: account.user == nil)
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

private struct AccountAvatar: View {
    let url: URL?
    let side: CGFloat

    @Environment(ImageStore.self) private var images
    @Environment(\.displayScale) private var displayScale
    @State private var image: PlatformImage?

    var body: some View {
        Group {
            if let image {
                Image(platformImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: side, height: side)
        .clipShape(.circle)
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            let pixels = Int((side * displayScale).rounded())
            image = await images.image(at: url, width: pixels, height: pixels)
        }
    }
}
