import SwiftUI

struct SignInView: View {
    @Environment(AccountStore.self) private var account
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    private var isAwaitingApproval: Bool {
        if case .awaitingApproval = account.state { return true }
        return false
    }

    /// The app's name and the one thing to do: no card, icon, or intro.
    var body: some View {
        VStack(spacing: 24) {
            Text("Plex Dev Tools")
                .font(.largeTitle.weight(.semibold))
            Group {
                switch account.state {
                case .awaitingApproval:
                    approval
                default:
                    signedOut
                }
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: isAwaitingApproval)

            if let message = account.errorMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { WellBackground() }
        .onChange(of: account.approvalURL) { _, url in
            if let url { openURL(url) }
        }
    }

    private var signedOut: some View {
        Button {
            Task { await account.beginSignIn() }
        } label: {
            Text("Sign In with Plex")
                .frame(minWidth: 180)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)
    }

    private var approval: some View {
        VStack(spacing: 16) {
            Text("Approve this sign-in in your browser.")
                .foregroundStyle(.secondary)

            ProgressView()
                .controlSize(.small)

            HStack {
                Button("Cancel", role: .cancel) { account.cancelSignIn() }
                Button("Open plex.tv Again") {
                    if let url = account.approvalURL { openURL(url) }
                }
            }
            .controlSize(.regular)
        }
    }
}
