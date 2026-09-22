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

    init(plexTV: PlexTVClient) {
        self.plexTV = plexTV
    }

    var user: PlexUser? {
        if case .signedIn(let user) = state { return user }
        return nil
    }

    func restore() async {
        guard let saved = TokenStore.load() else {
            state = .signedOut
            return
        }
        do {
            let user = try await plexTV.currentUser(token: saved)
            token = saved
            state = .signedIn(user)
        } catch PlexTVError.status(401) {
            TokenStore.delete()
            state = .signedOut
        } catch {
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
        pollTask?.cancel()
        pollTask = nil
        state = .signedOut
    }

    func signOut() {
        pollTask?.cancel()
        pollTask = nil
        TokenStore.delete()
        token = nil
        state = .signedOut
    }

    private func startPolling(_ pin: PlexPIN) {
        pollTask?.cancel()
        pollTask = Task { [plexTV] in
            // Strong PINs live ~30 minutes; stop a little short of that.
            for _ in 0..<800 {
                try? await Task.sleep(for: .seconds(2))
                if Task.isCancelled { return }
                guard let polled = try? await plexTV.pollPIN(id: pin.id) else { continue }
                guard let authToken = polled.authToken, !authToken.isEmpty else { continue }
                await completeSignIn(token: authToken)
                return
            }
            errorMessage = "The sign-in code expired. Try again."
            state = .signedOut
        }
    }

    private func completeSignIn(token: String) async {
        do {
            let user = try await plexTV.currentUser(token: token)
            try TokenStore.save(token)
            self.token = token
            state = .signedIn(user)
        } catch {
            errorMessage = error.localizedDescription
            state = .signedOut
        }
    }
}
