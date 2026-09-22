import SwiftUI

/// Signing out can't be undone without a fresh plex.tv approval, so every
/// entry point (Settings, the App menu) confirms through this one dialog.
private struct SignOutConfirmation: ViewModifier {
    @Binding var isPresented: Bool
    let onSignOut: () -> Void

    @Environment(AccountStore.self) private var account
    @Environment(ServerStore.self) private var servers

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Sign out of \(account.user?.title ?? "Plex")?",
            isPresented: $isPresented,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) {
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
