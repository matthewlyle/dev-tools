import SwiftUI

struct SignInView: View {
    @Environment(AccountStore.self) private var account

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "terminal")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)

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
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
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
                Text("Sign in with Plex")
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
                .font(.system(size: 34, weight: .medium, design: .monospaced))
                .tracking(4)
                .textSelection(.enabled)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.quaternary, in: .rect(cornerRadius: 12))

            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Waiting for approval…")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)

            HStack {
                Button("Cancel", role: .cancel) { account.cancelSignIn() }
                Button("Open plex.tv Again") { account.openApprovalPage() }
            }
            .controlSize(.regular)
        }
    }
}
