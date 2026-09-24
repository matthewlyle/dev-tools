import SwiftUI

/// Signing out can't be undone without a fresh plex.tv approval, so every
/// entry point (Settings, the App menu) confirms through this one dialog,
/// which is also the one place the session is torn down: the views that
/// would otherwise stop the stream and drop state are gone once signed out.
private struct SignOutConfirmation: ViewModifier {
    @Binding var isPresented: Bool
    let onSignOut: () -> Void

    @Environment(AccountStore.self) private var account
    @Environment(ServerStore.self) private var servers
    @Environment(ActivityStore.self) private var activity
    @Environment(RequestStore.self) private var requests
    @Environment(MediaQueryStore.self) private var mediaQuery
    @Environment(ImageStore.self) private var images
    @Environment(LightboxStore.self) private var lightbox
    @Environment(ValueMemory.self) private var memory

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Sign out of \(account.user?.title ?? "Plex")?",
            isPresented: $isPresented,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) {
                lightbox.close()
                activity.endSession()
                requests.resetAllWorkspaces()
                requests.resetServerCaches()
                memory.forgetSeen()
                mediaQuery.reset()
                images.removeAll()
                account.signOut()
                servers.clear()
                onSignOut()
            }
        } message: {
            Text("You'll need to approve a new sign-in on plex.tv to use the app again.")
        }
    }
}

extension View {
    func signOutConfirmation(isPresented: Binding<Bool>, onSignOut: @escaping () -> Void = {}) -> some View {
        modifier(SignOutConfirmation(isPresented: isPresented, onSignOut: onSignOut))
    }
}
