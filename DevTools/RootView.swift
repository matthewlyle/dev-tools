import SwiftUI

struct RootView: View {
    @Environment(AccountStore.self) private var account
    @Environment(ServerStore.self) private var servers

    var body: some View {
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
        .task { await account.restore() }
        .task(id: account.token) {
            guard let token = account.token else { return }
            await servers.refresh(token: token)
        }
    }
}
