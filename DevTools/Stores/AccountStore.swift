import Foundation
import Observation

/// The Plex account and its token. Tokens are Plex JWTs, which live 7 days:
/// the store renews one a day before it expires, from a device JWT signed
/// with this install's key, so a sign-in lasts until it's signed out or the
/// device is revoked at plex.tv.
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
    private var renewTask: Task<Void, Never>?
    private var cachedKey: DeviceKey?

    /// How long before expiry a token is renewed, and how soon a renewal that
    /// failed for want of a network is tried again.
    private static let renewalLead: TimeInterval = 24 * 60 * 60
    private static let retryDelay: TimeInterval = 60 * 60
    private static let scope = "username,email,friendly_name"

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
            let current = try await usableToken(from: saved)
            let user = try await plexTV.currentUser(token: current)
            adopt(current, user: user)
        } catch PlexTVError.status(let code) where (400..<500).contains(code) {
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
            let pin = try await plexTV.createPIN(jwk: try deviceKey().jwk)
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
        renewTask?.cancel()
        renewTask = nil
        TokenStore.delete()
        token = nil
        state = .signedOut
    }

    private func deviceKey() throws -> DeviceKey {
        if let cachedKey { return cachedKey }
        let key = try DeviceKey.loadOrCreate()
        cachedKey = key
        return key
    }

    /// A saved JWT as-is while it has a day left, renewed otherwise. A legacy
    /// token from before JWTs registers this device's key and is traded for
    /// one; if plex.tv won't, the legacy token still works and is kept.
    private func usableToken(from saved: String) async throws -> String {
        if PlexToken.isJWT(saved) {
            guard let expiry = PlexToken.expiry(of: saved), expiry.timeIntervalSinceNow > Self.renewalLead else {
                return try await renew()
            }
            return saved
        }
        do {
            try await plexTV.registerKey(jwk: try deviceKey().jwk, token: saved)
            return try await renew()
        } catch PlexTVError.status(401) {
            throw PlexTVError.status(401)
        } catch {
            return saved
        }
    }

    private func renew() async throws -> String {
        let key = try deviceKey()
        let clientIdentifier = plexTV.clientIdentifier, scope = Self.scope
        let renewed = try await plexTV.renewToken { nonce in
            try key.deviceJWT(clientIdentifier: clientIdentifier, nonce: nonce, scope: scope)
        }
        try TokenStore.save(renewed)
        return renewed
    }

    private func adopt(_ token: String, user: PlexUser) {
        try? TokenStore.save(token)
        self.token = token
        state = .signedIn(user)
        scheduleRenewal(of: token)
    }

    /// For a return to the foreground: the scheduled wake can land after the
    /// first request that needs the token.
    func renewIfDue() {
        guard let token, let expiry = PlexToken.expiry(of: token),
              expiry.timeIntervalSinceNow <= Self.renewalLead
        else { return }
        renewTask?.cancel()
        renewTask = Task { await renewNow() }
    }

    /// Wakes a day before the token expires and swaps in a fresh one, which
    /// the app picks up wherever it reads `token`. A revoked device is
    /// signed out; a renewal that fails otherwise tries again later.
    private func scheduleRenewal(of token: String) {
        renewTask?.cancel()
        guard let expiry = PlexToken.expiry(of: token) else { return }
        let wait = max(expiry.timeIntervalSinceNow - Self.renewalLead, 0)
        renewTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled, let self else { return }
            await self.renewNow()
        }
    }

    private func renewNow() async {
        do {
            let renewed = try await renew()
            self.token = renewed
            scheduleRenewal(of: renewed)
        } catch PlexTVError.status(let code) where (400..<500).contains(code) {
            errorMessage = "This device's sign-in was revoked. Sign in again."
            signOut()
        } catch {
            renewTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.retryDelay))
                guard !Task.isCancelled, let self else { return }
                await self.renewNow()
            }
        }
    }

    private func startPolling(_ pin: PlexPIN) {
        pollTask?.cancel()
        let clientIdentifier = plexTV.clientIdentifier
        pollTask = Task { [plexTV] in
            guard let key = try? deviceKey() else { return }
            // Strong PINs live ~30 minutes; stop a little short of that.
            for _ in 0..<800 {
                try? await Task.sleep(for: .seconds(2))
                if Task.isCancelled { return }
                guard let deviceJWT = try? key.deviceJWT(clientIdentifier: clientIdentifier),
                      let polled = try? await plexTV.pollPIN(id: pin.id, deviceJWT: deviceJWT),
                      let authToken = polled.authToken
                else { continue }
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
            adopt(token, user: user)
        } catch {
            errorMessage = error.localizedDescription
            state = .signedOut
        }
    }
}
