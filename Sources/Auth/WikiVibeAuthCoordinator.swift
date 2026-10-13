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
    /// True while a sign-in or sign-out is in flight, so buttons can disable.
    @Published private(set) var isBusy = false
    /// A caveat that is not a failure: a restored session the server could not
    /// be asked about, because the network is down.
    @Published private(set) var notice: String?

    /// How long the user has to finish in the browser before the listener gives
    /// up. Long enough to log in and clear a captcha, short enough that a
    /// forgotten window does not leave a port open all day.
    static let signInTimeout: TimeInterval = 300

    private let api: WikiVibeAuthAPIInterface
    private let store: WikiVibeSessionStoreInterface
    private var listener: WikiVibeCallbackServer?
    private var session: WikiVibeSession?

    init(api: WikiVibeAuthAPIInterface = WikiVibeAuthAPI(),
         store: WikiVibeSessionStoreInterface = KeychainWikiVibeSessionStore()) {
        self.api = api
        self.store = store
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
        guard let stored = store.load() else {
            state = .signedOut
            return
        }
        session = stored

        var current = stored
        if current.isExpired {
            do {
                current = try await api.refresh(using: current)
                session = current
                store.save(current)
            } catch WikiVibeAuthError.sessionExpired {
                await forgetLocalSession()
                return
            } catch {
                // Expired and unrefreshable right now: show the account, say
                // it is unconfirmed, and try again on the next launch.
                state = .signedIn(current.account)
                notice = L10n.t("Signed in, but the session could not be confirmed with WikiVibe.")
                return
            }
        }

        state = .signedIn(current.account)
        do {
            let account = try await api.account(for: current)
            session = current
            state = .signedIn(account)
            notice = nil
        } catch WikiVibeAuthError.sessionExpired {
            await forgetLocalSession()
        } catch {
            notice = L10n.t("Signed in, but the session could not be confirmed with WikiVibe.")
        }
    }

    // MARK: - Sign in

    /// Open the browser and wait for the code to come back to loopback.
    ///
    /// Every exit closes the listener: a port left open after a cancelled or
    /// failed attempt would be a socket the app is no longer watching, and the
    /// next sign-in would race it for the callback.
    func signIn() async {
        guard !isBusy else { return }
        isBusy = true
        notice = nil
        state = .signingIn
        defer { isBusy = false }

        do {
            let pkce = try WikiVibePKCE.generate()
            let server = try await WikiVibeCallbackServer.start(expectedState: pkce.state)
            listener = server
            defer { listener = nil }

            let url = try api.authorizationURL(
                pkce: pkce,
                redirectURI: WikiVibeAuthContract.redirectURI(port: server.port)
            )
            guard NSWorkspace.shared.open(url) else {
                await server.stop()
                throw WikiVibeAuthError.browserDidNotOpen
            }

            let outcome = try await server.waitForCallback(timeout: Self.signInTimeout)
            await server.stop()

            switch outcome {
            case .authorized(let code):
                let session = try await api.exchange(
                    code: code,
                    verifier: pkce.verifier,
                    redirectURI: WikiVibeAuthContract.redirectURI(port: server.port)
                )
                // Stored before it is adopted: a session the app uses but
                // cannot restore would be lost on the next launch, and the
                // user would be asked to sign in again for no stated reason.
                guard store.save(session) else { throw WikiVibeAuthError.storageFailed }
                self.session = session
                state = .signedIn(session.account)
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
            state = .failed(error.errorDescription ?? L10n.t("Sign-in failed."))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Abandon an in-flight sign-in and close its listener.
    func cancelSignIn() async {
        guard let listener else { return }
        self.listener = nil
        await listener.stop()
        if case .signingIn = state { state = .signedOut }
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
        session = nil
        store.clear()
        notice = nil
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
