import SwiftUI

struct RootView: View {
    @Environment(AccountStore.self) private var account
    @Environment(ServerStore.self) private var servers

    var body: some View {
        @Bindable var account = account

        Group {
            switch account.state {
            case .restoring:
                ProgressView()
                    .controlSize(.large)
            case .signedOut, .awaitingApproval:
                SignInView()
            case .signedIn:
                MainSplitView()
            }
        }
        .overlay { PosterFlightOverlay() }
        .overlay { LightboxOverlay() }
        .signOutConfirmation(isPresented: $account.isConfirmingSignOut)
        .task { await account.restore() }
        .task(id: account.token) {
            guard let token = account.token else { return }
            await servers.refresh(token: token)
        }
    }
}
