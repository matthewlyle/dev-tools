import SwiftUI

struct RootView: View {
    @Environment(AccountStore.self) private var account
    @Environment(ServerStore.self) private var servers
    @Environment(ActivityStore.self) private var activity
    @Environment(\.scenePhase) private var scenePhase
    @State private var wasInBackground = false

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
        .overlay { LightboxOverlay() }
        .signOutConfirmation(isPresented: $account.isConfirmingSignOut)
        .task { await account.restore() }
        .task(id: account.token) {
            guard let token = account.token else { return }
            await servers.refresh(token: token)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: wasInBackground = true
            case .active where wasInBackground:
                wasInBackground = false
                activity.resumeAfterBackground()
            default: break
            }
        }
    }
}
