import AuthenticationServices
import SwiftUI

struct SignInView: View {
    @Environment(AccountStore.self) private var account
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

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
        .task(id: account.approvalURL) {
            guard let url = account.approvalURL else { return }
            await approve(at: url)
        }
    }

    /// Plex's approval page in the system sign-in sheet. Polling finishes
    /// sign-in, which tears this task down and so dismisses the sheet;
    /// closing it by hand cancels. Nothing ever calls back on the scheme:
    /// Plex refuses a `forwardUrl` that isn't its own or the PIN's origin,
    /// and fails the approval instead.
    private func approve(at url: URL) async {
        do {
            _ = try await webAuthenticationSession.authenticate(
                using: url,
                callback: .customScheme("mldgg-devtools"),
                preferredBrowserSession: .shared,
                additionalHeaderFields: [:]
            )
        } catch {
            guard !Task.isCancelled, account.approvalURL == url else { return }
            account.cancelSignIn()
            if (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin {
                account.errorMessage = error.localizedDescription
            }
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
            Text("Approve this sign-in with Plex.")
                .foregroundStyle(.secondary)

            ProgressView()
                .controlSize(.small)

            Button("Cancel", role: .cancel) { account.cancelSignIn() }
                .controlSize(.regular)
        }
    }
}
