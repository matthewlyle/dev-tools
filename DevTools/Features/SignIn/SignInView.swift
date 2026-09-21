import SwiftUI

struct SignInView: View {
    @Environment(AccountStore.self) private var account

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "terminal")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("Plex Dev Tools")
                .font(.largeTitle.weight(.semibold))

            switch account.state {
            case .awaitingApproval(let pin):
                approval(pin)
            default:
                signedOut
            }

            if let message = account.errorMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
        }
        .padding(40)
        // Content layer, not chrome: standard material, not Liquid Glass.
        .background(.regularMaterial, in: .rect(cornerRadius: 28))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var signedOut: some View {
        VStack(spacing: 16) {
            Text("Sign in with your Plex account to discover your servers and start exploring the API.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

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
    }

    private func approval(_ pin: PlexPIN) -> some View {
        VStack(spacing: 16) {
            Text("Approve this sign-in in your browser.")
                .foregroundStyle(.secondary)

            Text(pin.code)
                .font(.code(size: 34, weight: .medium))
                .textSelection(.enabled)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.quaternary, in: .rect(cornerRadius: 12))

            // "Approve this sign-in in your browser." above already says
            // what's happening; HIG: don't label a spinner.
            ProgressView()
                .controlSize(.small)

            HStack {
                Button("Cancel", role: .cancel) { account.cancelSignIn() }
                Button("Open plex.tv Again") { account.openApprovalPage() }
            }
            .controlSize(.regular)
        }
    }
}
