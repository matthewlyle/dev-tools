import Foundation
import Observation

@MainActor
@Observable
final class AccountStore {
    enum State: Equatable {
        case restoring
        case signedOut
        case awaitingApproval(PlexPIN)
        case signedIn(PlexUser)
    }

    private(set) var state: State = .restoring
    private(set) var token: String?
    var errorMessage: String?
    /// Set by the Sign Out… menu command; the root view owns the confirmation.
    var isConfirmingSignOut = false

    private let plexTV: PlexTVClient
    private var pollTask: Task<Void, Never>?
    /// Bumped by sign-out and cancel, so a restore or approval still in
    /// flight can't sign back in the account just left.
    private var session = 0

    init(plexTV: PlexTVClient) {
        self.plexTV = plexTV
    }

    var user: PlexUser? {
        if case .signedIn(let user) = state { return user }
        return nil
    }

    func restore() async {
        let session = session
        guard let saved = TokenStore.load() else {
            state = .signedOut
            return
        }
        do {
            let user = try await plexTV.currentUser(token: saved)
            guard session == self.session else { return }
            token = saved
            state = .signedIn(user)
        } catch PlexTVError.status(401) {
            guard session == self.session else { return }
            TokenStore.delete()
            state = .signedOut
        } catch {
            guard session == self.session else { return }
            errorMessage = error.localizedDescription
            state = .signedOut
        }
    }

    func beginSignIn() async {
        errorMessage = nil
        do {
            let pin = try await plexTV.createPIN()
            state = .awaitingApproval(pin)
            startPolling(pin)
        } catch {
            errorMessage = error.localizedDescription
            state = .signedOut
        }
    }

    /// Where the pending sign-in is approved; the view opens it.
    var approvalURL: URL? {
        guard case .awaitingApproval(let pin) = state else { return nil }
        return plexTV.approvalURL(for: pin)
    }

    func cancelSignIn() {
        session += 1
        pollTask?.cancel()
        pollTask = nil
        state = .signedOut
    }

    func signOut() {
        session += 1
        pollTask?.cancel()
        pollTask = nil
        if !TokenStore.delete() {
            errorMessage = "Couldn't remove your sign-in from the Keychain, so the app may sign you back in when it next opens. Sign in and out again to retry."
        }
        token = nil
        state = .signedOut
    }

    private func startPolling(_ pin: PlexPIN) {
        pollTask?.cancel()
        let session = session
        pollTask = Task { [plexTV] in
            // Strong PINs live ~30 minutes; stop a little short of that.
            for _ in 0..<800 {
                try? await Task.sleep(for: .seconds(2))
                if Task.isCancelled { return }
                guard let polled = try? await plexTV.pollPIN(id: pin.id) else { continue }
                guard let authToken = polled.authToken, !authToken.isEmpty else { continue }
                await completeSignIn(token: authToken, session: session)
                return
            }
            errorMessage = "The sign-in code expired. Try again."
            state = .signedOut
        }
    }

    private func completeSignIn(token: String, session: Int) async {
        do {
            let user = try await plexTV.currentUser(token: token)
            guard session == self.session else { return }
            try TokenStore.save(token)
            self.token = token
            state = .signedIn(user)
        } catch {
            guard session == self.session else { return }
            errorMessage = error.localizedDescription
            state = .signedOut
        }
    }
}
