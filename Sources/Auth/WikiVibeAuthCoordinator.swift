import AppKit
import Foundation

/// What the account window can show about sign-in.
enum WikiVibeAuthState: Equatable {
    /// No session, and none being attempted.
    case signedOut
    /// The browser is open and the app is waiting for the return.
    case signingIn
    /// A session the app holds. The account came from the server.
    case signedIn(WikiVibeAccount)
    /// The last attempt ended without a session. The reason is the message.
    case failed(String)
}

/// Owns the sign-in lifecycle: restore, authorize, renew, sign out.
///
/// Deliberately the only object that holds a session. The tokens never reach a
/// view, a log line or `UserDefaults`; the window sees a state and an account
/// name, and the keychain sees the session only when it changes.
///
/// Sign-in runs in the system browser, not a web view. A web view would keep
/// the user's WikiVibe credentials inside a process the app controls and could
/// read, and the panel's login has a captcha and an email-code step that a
/// native form cannot honestly reproduce. The browser keeps the password where
/// it belongs, and the app gets back only a one-time code bound to a PKCE
/// verifier it generated.
@MainActor
final class WikiVibeAuthCoordinator: ObservableObject {
    @Published private(set) var state: WikiVibeAuthState = .signedOut
    /// The account's money, when the server has been asked and answered. Nil
    /// while unknown — the window shows nothing rather than a zero it invented.
    @Published private(set) var wallet: WikiVibeWallet?
    /// True while a sign-in or sign-out is in flight, so buttons can disable.
    @Published private(set) var isBusy = false
    /// True while the balance is being fetched, so the window can say so.
    @Published private(set) var isLoadingWallet = false
    /// Why the balance is unavailable, when it is.
    @Published private(set) var walletError: String?
    /// A caveat that is not a failure: a restored session the server could not
    /// be asked about, because the network is down.
    @Published private(set) var notice: String?

    /// How long the user has to finish in the browser before the listener gives
    /// up. Long enough to log in and clear a captcha, short enough that a
    /// forgotten window does not leave a port open all day.
    static let signInTimeout: TimeInterval = 300

    /// How often the balance is re-read while the app is signed in.
    ///
    /// A balance is a number other machines change: usage on another device
    /// moves it without this app doing anything, so a figure read once at
    /// sign-in quietly goes stale. A minute is the same interval the backend
    /// specification proposes for account polling.
    static let walletRefreshInterval: TimeInterval = 60

    /// The same poll, faster, while the account window is on screen.
    ///
    /// The row in the notch can lag a minute without anyone noticing; a window
    /// someone is looking at cannot, and that is the only moment a shorter
    /// interval costs anything. The poll reads this each time round, so opening
    /// or closing the window changes the rate without restarting it.
    static let walletRefreshIntervalVisible: TimeInterval = 15

    /// True while the account window is on screen, which shortens the poll.
    private var walletIsVisible = false

    private let api: WikiVibeAuthAPIInterface
    private let store: WikiVibeSessionStoreInterface
    private let defaults: UserDefaults
    private let openAuthorizationURL: (URL) -> Bool
    private static let restoreBlockedKey = "auth.restoreBlockedAfterSignOut"
    private var listener: WikiVibeCallbackServer?
    private var signInAttempt: UUID?
    private var session: WikiVibeSession?
    private var renewal: (original: WikiVibeSession, task: Task<WikiVibeSession, Error>)?
    private var previousSession: WikiVibeSession?
    private var sessionGeneration = UUID()
    /// The balance poll, alive only while there is a session to poll with.
    private var walletTask: Task<Void, Never>?

    init(api: WikiVibeAuthAPIInterface = WikiVibeAuthAPI(),
         store: WikiVibeSessionStoreInterface = KeychainWikiVibeSessionStore(),
         defaults: UserDefaults = .standard,
         openAuthorizationURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }) {
        self.api = api
        self.store = store
        self.defaults = defaults
        self.openAuthorizationURL = openAuthorizationURL
    }

    /// The account the app is signed in as, for the window's own use.
    var account: WikiVibeAccount? {
        if case .signedIn(let account) = state { return account }
        return nil
    }

    // MARK: - Restore

    /// Pick up where the last launch left off.
    ///
    /// Runs on every launch, and only ever moves *towards* signed out when the
    /// server actually says so. A stored session that cannot be reached is kept
    /// and marked unverified: dropping it would sign the user out every time
    /// the network is down, which is both wrong and unrecoverable without
    /// another trip through the browser.
    func restore() async {
        guard case .signedOut = state, session == nil else { return }
        guard !defaults.bool(forKey: Self.restoreBlockedKey) else {
            if store.clear() {
                defaults.removeObject(forKey: Self.restoreBlockedKey)
                notice = nil
            } else {
                notice = L10n.t("The saved session could not be deleted. Automatic sign-in is blocked. Unlock Keychain and restart the app to retry deletion.")
            }
            return
        }
        guard let stored = store.load() else {
            state = .signedOut
            return
        }
        session = stored
        // The account view can request a balance while restoration is awaiting
        // the network. Do not rotate the same refresh token concurrently.
        isLoadingWallet = true
        defer { isLoadingWallet = false }

        var current = stored
        if current.isExpired {
            do {
                current = try await renewSession(current)
            } catch WikiVibeAuthError.sessionExpired {
                guard session == current else { return }
                await forgetLocalSession()
                return
            } catch {
                guard session == current else { return }
                // Keep polling so a launch while offline recovers without restart.
                state = .signedIn(current.account)
                notice = L10n.t("Signed in, but the session could not be confirmed with WikiVibe.")
                startWalletPolling()
                return
            }
        }

        state = .signedIn(current.account)
        do {
            let account = try await api.account(for: current)
            guard session == current else { return }
            state = .signedIn(account)
            notice = nil
        } catch WikiVibeAuthError.sessionExpired {
            guard session == current else { return }
            await forgetLocalSession()
            return
        } catch {
            guard session == current else { return }
            notice = L10n.t("Signed in, but the session could not be confirmed with WikiVibe.")
        }
        isLoadingWallet = false
        await loadWallet()
        startWalletPolling()
    }

    /// Fetch the account's money and publish it, or publish why it is missing.
    ///
    /// Deliberately not fatal: a balance that could not be read leaves the app
    /// signed in, because the session is fine — only the number is unknown. The
    /// window keeps showing the account and says what happened to the money row
    /// rather than quietly dropping it.
    func loadWallet() async {
        guard var current = session, !isLoadingWallet else { return }
        isLoadingWallet = true
        defer { isLoadingWallet = false }
        do {
            let renewedBeforeRequest = current.isExpired
            if renewedBeforeRequest {
                current = try await renewSession(current)
            }
            let result: WikiVibeWallet
            do {
                result = try await api.wallet(for: current)
            } catch WikiVibeAuthError.sessionExpired where !renewedBeforeRequest {
                // The server can expire access before the local clock does.
                // Renew once, then retry; never loop on a refused credential.
                current = try await renewSession(current)
                result = try await api.wallet(for: current)
            }
            guard session == current else { return }
            wallet = result
            walletError = nil
            notice = nil
        } catch WikiVibeAuthError.sessionExpired {
            guard session == current else { return }
            await forgetLocalSession()
        } catch {
            guard session == current else { return }
            wallet = nil
            walletError = error.localizedDescription
        }
    }

    /// Wallet and key requests share one rotation of a refresh credential.
    private func renewSession(_ current: WikiVibeSession) async throws -> WikiVibeSession {
        if let renewal, renewal.original == current { return try await renewal.task.value }
        // A parallel request may already have completed the same rotation.
        if previousSession == current, let session { return session }
        guard session == current else { throw CancellationError() }
        let task = Task { @MainActor in
            let renewed = try await api.refresh(using: current)
            guard session == current else { throw CancellationError() }
            session = renewed
            previousSession = current
            store.save(renewed)
            return renewed
        }
        renewal = (current, task)
        defer { if renewal?.original == current { renewal = nil } }
        return try await task.value
    }

    /// Only this owner gives the account credential to the read-only panel API.
    /// A response from a signed-out session can never repopulate the key card.
    func accountAPIKeys(using keysAPI: WikiVibeKeysAPIInterface) async throws -> [WikiVibeAccountKey] {
        guard var current = session, account != nil else { throw WikiVibeKeysError.notSignedIn }
        let generation = sessionGeneration
        do {
            let renewedBeforeRequest = current.isExpired
            if renewedBeforeRequest { current = try await renewSession(current) }
            let keys: [WikiVibeAccountKey]
            do {
                keys = try await keysAPI.keys(accessToken: current.accessToken)
            } catch WikiVibeKeysError.unauthorized where !renewedBeforeRequest {
                guard generation == sessionGeneration else { throw CancellationError() }
                current = try await renewSession(current)
                keys = try await keysAPI.keys(accessToken: current.accessToken)
            }
            // A wallet refresh of this account does not invalidate a key list.
            guard generation == sessionGeneration, session?.account.id == current.account.id, account != nil else { throw CancellationError() }
            return keys
        } catch WikiVibeKeysError.unauthorized {
            if session == current { await forgetLocalSession() }
            throw WikiVibeKeysError.notSignedIn
        } catch WikiVibeAuthError.sessionExpired {
            if session == current { await forgetLocalSession() }
            throw WikiVibeKeysError.notSignedIn
        }
    }

    /// Start re-reading the balance while signed in.
    ///
    /// Idempotent: called on restore, after sign-in and when the window opens,
    /// and only one poll ever runs. The task holds no session of its own — it
    /// reads whatever `session` currently is, so a sign-out stops it instead of
    /// letting a stale token keep polling.
    func startWalletPolling() {
        guard walletTask == nil, session != nil else { return }
        walletTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval = await self?.currentWalletInterval() ?? Self.walletRefreshInterval
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if Task.isCancelled { return }
                guard let self else { return }
                guard await self.session != nil else { return }
                await self.loadWallet()
            }
        }
    }

    /// The interval the poll should use right now.
    func currentWalletInterval() -> TimeInterval {
        walletIsVisible ? Self.walletRefreshIntervalVisible : Self.walletRefreshInterval
    }

    /// Tell the coordinator whether the window is on screen. Only the interval
    /// changes; the poll itself is not restarted, so no reading is skipped.
    func setWalletVisible(_ visible: Bool) {
        walletIsVisible = visible
    }

    /// Stop re-reading. Called on sign-out and when the app goes away.
    func stopWalletPolling() {
        walletTask?.cancel()
        walletTask = nil
    }

    // MARK: - Sign in

    /// Open the browser and wait for the code to come back to loopback.
    ///
    /// Every exit closes the listener: a port left open after a cancelled or
    /// failed attempt would be a socket the app is no longer watching, and the
    /// next sign-in would race it for the callback.
    func signIn() async {
        guard !isBusy else { return }
        let attempt = UUID()
        signInAttempt = attempt
        isBusy = true
        notice = nil
        state = .signingIn
        defer {
            isBusy = false
            if signInAttempt == attempt { signInAttempt = nil }
        }

        do {
            let pkce = try WikiVibePKCE.generate()
            let server = try await WikiVibeCallbackServer.start(expectedState: pkce.state)
            guard signInAttempt == attempt else {
                await server.stop()
                return
            }
            listener = server
            defer { listener = nil }

            let url = try api.authorizationURL(
                pkce: pkce,
                redirectURI: WikiVibeAuthContract.redirectURI(port: server.port)
            )
            guard openAuthorizationURL(url) else {
                await server.stop()
                throw WikiVibeAuthError.browserDidNotOpen
            }

            let outcome = try await server.waitForCallback(timeout: Self.signInTimeout)
            await server.stop()
            guard signInAttempt == attempt else { return }

            switch outcome {
            case .authorized(let code):
                let session = try await api.exchange(
                    code: code,
                    verifier: pkce.verifier,
                    redirectURI: WikiVibeAuthContract.redirectURI(port: server.port)
                )
                guard signInAttempt == attempt else { return }
                // Stored before it is adopted: a session the app uses but
                // cannot restore would be lost on the next launch, and the
                // user would be asked to sign in again for no stated reason.
                guard store.save(session) else { throw WikiVibeAuthError.storageFailed }
                defaults.removeObject(forKey: Self.restoreBlockedKey)
                self.session = session
                state = .signedIn(session.account)
                await loadWallet()
                startWalletPolling()
            case .denied(let reason):
                state = .failed(L10n.t("WikiVibe refused the sign-in: \(reason)"))
            case .timedOut:
                state = .failed(L10n.t("Sign-in was not completed in time."))
            case .cancelled:
                state = .signedOut
            case .mismatch:
                // The listener keeps waiting for the real callback, so this is
                // unreachable; treated as a failure rather than ignored.
                state = .failed(L10n.t("The sign-in response did not match this request."))
            case .malformed(let reason):
                state = .failed(L10n.t("The sign-in response was not usable: \(reason)"))
            }
        } catch let error as WikiVibeAuthError {
            guard signInAttempt == attempt else { return }
            state = .failed(error.errorDescription ?? L10n.t("Sign-in failed."))
        } catch {
            guard signInAttempt == attempt else { return }
            state = .failed(error.localizedDescription)
        }
    }

    /// Abandon an in-flight sign-in and close its listener.
    func cancelSignIn() async {
        signInAttempt = nil
        if case .signingIn = state { state = .signedOut }
        let listener = self.listener
        self.listener = nil
        await listener?.stop()
    }

    // MARK: - Sign out

    /// End the session locally and, best effort, on the server.
    ///
    /// The keychain is cleared even if the server cannot be reached: the user
    /// asked to be signed out of *this* machine, and leaving a usable refresh
    /// token behind because a request timed out is the opposite of that. The
    /// server call revokes the refresh token specifically — not every session
    /// the account has, which would sign the user out of the website too.
    func signOut() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        await cancelSignIn()
        let token = session?.refreshToken
        await forgetLocalSession()
        if let token {
            await api.revoke(refreshToken: token)
        }
    }

    /// Drop everything this machine holds, without touching the server.
    private func forgetLocalSession() async {
        stopWalletPolling()
        renewal?.task.cancel()
        renewal = nil
        previousSession = nil
        sessionGeneration = UUID()
        defaults.set(true, forKey: Self.restoreBlockedKey)
        session = nil
        let cleared = store.clear()
        if cleared { defaults.removeObject(forKey: Self.restoreBlockedKey) }
        notice = cleared ? nil : L10n.t("The saved session could not be deleted. Automatic sign-in is blocked. Unlock Keychain and restart the app to retry deletion.")
        // The money belongs to the session that read it. Leaving it on screen
        // after sign-out would keep showing a balance for an account the app no
        // longer has a session for.
        wallet = nil
        walletError = nil
        state = .signedOut
    }
}

/// The slice of the session store the coordinator uses.
///
/// A protocol rather than the enum directly so the lifecycle can be tested
/// without a login keychain: `SecItemCopyMatching` cannot run in a unit test
/// bundle, and the transitions that matter — restore, expired refresh, sign-out
/// with an unreachable server — are exactly the ones worth testing.
protocol WikiVibeSessionStoreInterface: AnyObject {
    func load() -> WikiVibeSession?
    @discardableResult func save(_ session: WikiVibeSession) -> Bool
    @discardableResult func clear() -> Bool
}

final class KeychainWikiVibeSessionStore: WikiVibeSessionStoreInterface {
    func load() -> WikiVibeSession? { WikiVibeSessionStore.load() }
    func save(_ session: WikiVibeSession) -> Bool { WikiVibeSessionStore.save(session) }
    func clear() -> Bool { WikiVibeSessionStore.clear() }
}
