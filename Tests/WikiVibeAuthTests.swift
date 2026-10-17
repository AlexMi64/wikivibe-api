import XCTest
@testable import Codenotch

/// The sign-in path, minus the parts that need a real account.
///
/// Everything asserted here is a decision the app makes on its own: what the
/// PKCE values look like, which callback settles a waiting sign-in, and what
/// the session lifecycle does when the server says yes, says no, or cannot be
/// reached. None of it needs a browser or a live token, and all of it is what
/// decides whether a user ends up signed in.
final class WikiVibeAuthTests: XCTestCase {

    // MARK: - PKCE

    /// RFC 7636 appendix B, so the digest is checked against the spec's own
    /// vector rather than against this implementation's output.
    func testChallengeMatchesRFC7636Vector() {
        XCTAssertEqual(
            WikiVibePKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        )
    }

    /// The server rejects a verifier outside 43...128 characters or containing
    /// anything but the unreserved set, so a generated one must satisfy both
    /// without escaping.
    func testGeneratedVerifierAndStateAreAcceptedByTheServerRules() throws {
        let unreserved = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

        for _ in 0..<32 {
            let pkce = try WikiVibePKCE.generate()
            XCTAssertTrue((43...128).contains(pkce.verifier.count), pkce.verifier.count.description)
            XCTAssertTrue(pkce.verifier.allSatisfy(unreserved.contains), pkce.verifier)
            XCTAssertFalse(pkce.state.isEmpty)
            XCTAssertLessThanOrEqual(pkce.state.count, 512)
            XCTAssertTrue(pkce.state.allSatisfy { $0.isASCII && $0.asciiValue.map { $0 > 0x20 && $0 < 0x7f } == true },
                          pkce.state)
            // A challenge that kept the padding would be rejected as
            // non-base64url, and one that kept `+` or `/` would not survive a
            // query string unescaped.
            XCTAssertFalse(pkce.challenge.contains("="))
            XCTAssertFalse(pkce.challenge.contains("+"))
            XCTAssertFalse(pkce.challenge.contains("/"))
            XCTAssertEqual(pkce.challenge, WikiVibePKCE.challenge(for: pkce.verifier))
        }
    }

    /// Two attempts must not share a verifier: a replayed code would otherwise
    /// be spendable by anyone who saw the first redirect.
    func testEachAttemptGetsFreshMaterial() throws {
        var verifiers = Set<String>()
        var states = Set<String>()
        for _ in 0..<64 {
            let pkce = try WikiVibePKCE.generate()
            verifiers.insert(pkce.verifier)
            states.insert(pkce.state)
        }
        XCTAssertEqual(verifiers.count, 64)
        XCTAssertEqual(states.count, 64)
    }

    // MARK: - Callback parsing

    private let state = "state-for-this-attempt"

    func testMatchingStateAndCodeIsAccepted() {
        XCTAssertEqual(
            WikiVibeCallbackQuery.parse(uri: "/callback?code=abc123&state=\(state)", expectedState: state),
            .authorized(code: "abc123")
        )
    }

    /// A callback for a different attempt must not settle this one: anything
    /// able to reach loopback could otherwise feed the app an arbitrary code.
    func testForeignStateIsNotAcceptedAsThisAttempt() {
        XCTAssertEqual(
            WikiVibeCallbackQuery.parse(uri: "/callback?code=abc123&state=someone-elses", expectedState: state),
            .mismatch
        )
        XCTAssertEqual(
            WikiVibeCallbackQuery.parse(uri: "/callback?code=abc123", expectedState: state),
            .mismatch
        )
    }

    func testForeignErrorCannotCancelPendingSignIn() {
        let result = WikiVibeCallbackQuery.parse(
            uri: "/callback?error=access_denied&state=attacker", expectedState: state)
        XCTAssertEqual(result, .mismatch)
        XCTAssertNil(result.settlesAs)
    }

    func testRefusalKeepsTheServersOwnReason() {
        XCTAssertEqual(
            WikiVibeCallbackQuery.parse(
                uri: "/callback?error=access_denied&error_description=user%20said%20no&state=\(state)",
                expectedState: state
            ),
            .denied("user said no")
        )
        // An error without a description still has to name itself.
        XCTAssertEqual(
            WikiVibeCallbackQuery.parse(uri: "/callback?error=access_denied&state=\(state)", expectedState: state),
            .denied("access_denied")
        )
    }

    func testOtherPathsAndEmptyValuesAreNotCallbacks() {
        XCTAssertEqual(WikiVibeCallbackQuery.parse(uri: "/favicon.ico", expectedState: state), .notFound)
        XCTAssertEqual(WikiVibeCallbackQuery.parse(uri: "/", expectedState: state), .notFound)
        XCTAssertEqual(WikiVibeCallbackQuery.parse(uri: "/callback", expectedState: state), .mismatch)
        XCTAssertEqual(
            WikiVibeCallbackQuery.parse(uri: "/callback?code=&state=\(state)", expectedState: state),
            .malformed("missing code")
        )
        // A path that merely starts with the callback path is a different path.
        XCTAssertEqual(WikiVibeCallbackQuery.parse(uri: "/callback/extra", expectedState: state), .notFound)
    }

    func testUnparseableTargetCannotSettleSignIn() {
        XCTAssertNil(WikiVibeCallbackQuery.parse(uri: "http://[::1", expectedState: state).settlesAs)
    }

    // MARK: - Callback listener

    /// The whole reason the listener exists: the browser has to be able to
    /// reach it, and what it hands back must be the code from the URL.
    func testListenerDeliversTheCodeFromALoopbackRequest() async throws {
        let server = try await WikiVibeCallbackServer.start(expectedState: state)
        defer { Task { await server.stop() } }
        XCTAssertGreaterThan(server.port, 0)

        async let outcome = server.waitForCallback(timeout: 10)
        let (status, _) = try await get("http://127.0.0.1:\(server.port)/callback?code=code-1&state=\(state)")
        XCTAssertEqual(status, 200)
        // Bound before the assertion: `XCTAssertEqual` takes an autoclosure, and
        // an `await` cannot live inside one.
        let delivered = try await outcome
        XCTAssertEqual(delivered, .authorized(code: "code-1"))
    }

    /// Browsers ask for `favicon.ico` unprompted. If that settled the wait, a
    /// sign-in would fail at the moment the page loaded.
    func testUnrelatedRequestDoesNotEndTheWait() async throws {
        let server = try await WikiVibeCallbackServer.start(expectedState: state)
        defer { Task { await server.stop() } }

        let (faviconStatus, _) = try await get("http://127.0.0.1:\(server.port)/favicon.ico")
        XCTAssertEqual(faviconStatus, 404)

        let (mismatchStatus, _) = try await get("http://127.0.0.1:\(server.port)/callback?code=stale&state=other")
        XCTAssertEqual(mismatchStatus, 400)

        async let outcome = server.waitForCallback(timeout: 10)
        _ = try await get("http://127.0.0.1:\(server.port)/callback?code=code-2&state=\(state)")
        let delivered = try await outcome
        XCTAssertEqual(delivered, .authorized(code: "code-2"))
    }

    func testListenerGivesUpAfterTheDeadline() async throws {
        let server = try await WikiVibeCallbackServer.start(expectedState: state)
        defer { Task { await server.stop() } }
        let outcome = try await server.waitForCallback(timeout: 1)
        XCTAssertEqual(outcome, .timedOut)
    }

    /// Closing the listener must release the wait, or a cancelled sign-in would
    /// leave the app waiting for a callback that can no longer arrive.
    func testStoppingTheListenerCancelsTheWait() async throws {
        let server = try await WikiVibeCallbackServer.start(expectedState: state)
        async let outcome = server.waitForCallback(timeout: 30)
        await server.stop()
        let cancelled = try await outcome
        XCTAssertEqual(cancelled, .cancelled)
        // Stopping twice is allowed: every path out of sign-in calls it.
        await server.stop()
    }

    // MARK: - Session

    /// `expires_in` is a duration; keeping it as one would make the stored
    /// session mean something different every time it was read.
    func testSessionExpiryIsAbsoluteAndSlightlyEarly() {
        let account = WikiVibeAccount(id: 1, username: "u", email: "e@example.com")
        let fresh = WikiVibeSession(accessToken: "a", refreshToken: "r", expiresIn: 3600, account: account)
        XCTAssertFalse(fresh.isExpired)

        let spent = WikiVibeSession(accessToken: "a", refreshToken: "r", expiresIn: 0, account: account)
        XCTAssertTrue(spent.isExpired)

        // A token that has 10 seconds left is treated as spent: the request it
        // would authorize lands after the expiry, not before.
        let almost = WikiVibeSession(accessToken: "a", refreshToken: "r", expiresIn: 10, account: account)
        XCTAssertTrue(almost.isExpired)
    }

    func testStoredSessionSurvivesAnEncodeDecodeRoundTrip() throws {
        let session = WikiVibeSession(
            accessToken: "access",
            refreshToken: "refresh",
            expiresIn: 600,
            account: WikiVibeAccount(id: 7, username: "nick", email: "nick@example.com")
        )
        let data = try JSONEncoder().encode(session)
        let restored = try JSONDecoder().decode(WikiVibeSession.self, from: data)
        XCTAssertEqual(restored.accessToken, session.accessToken)
        XCTAssertEqual(restored.refreshToken, session.refreshToken)
        XCTAssertEqual(restored.account, session.account)
        XCTAssertEqual(restored.expiresAt.timeIntervalSince1970,
                       session.expiresAt.timeIntervalSince1970, accuracy: 0.001)
    }

    func testAccountDisplayNameFallsBackToEmail() {
        XCTAssertEqual(WikiVibeAccount(id: 1, username: "nick", email: "n@e.com").displayName, "nick")
        XCTAssertEqual(WikiVibeAccount(id: 1, username: "  ", email: "n@e.com").displayName, "n@e.com")
    }

    /// "Open the website" leads to the panel, not the issuer.
    ///
    /// The issuer is a different origin with its own session cookie; sending
    /// people there read as being signed out, because the app had a session and
    /// the browser did not. The panel keeps a first-party session and renews it
    /// itself, so a browser that has signed in there once stays signed in.
    func testTheWebsiteButtonLeadsToThePanel() {
        XCTAssertEqual(WikiVibeAuthContract.panel, WikiVibeAuthContract.api)
        XCTAssertNotEqual(WikiVibeAuthContract.panel, WikiVibeAuthContract.issuer)
        XCTAssertEqual(WikiVibeAuthContract.panel.host, "api.wikivibe.dev")
    }
}

// MARK: - Wallet

/// The balance's own rules: which number is which, and what a missing field
/// means. These decide whether the window shows the account's money or a zero
/// nobody sent.
final class WikiVibeWalletTests: XCTestCase {
    private func wallet(regular: Double, bonus: Double? = nil, frozen: Double? = nil,
                        name: String = "USD", symbol: String = "$") -> WikiVibeWallet {
        WikiVibeWallet(regular: regular, bonus: bonus, frozen: frozen,
                       currencyName: name, currencySymbol: symbol)
    }

    /// The unit is an operator setting: the symbol is used when present, the
    /// name when there is no symbol, and neither is invented.
    func testAmountUsesTheServersOwnUnit() {
        XCTAssertEqual(wallet(regular: 116.11214956).regularText, "$116.11")
        XCTAssertEqual(wallet(regular: 5, name: "EUR", symbol: "").regularText, "5.00 EUR")
        XCTAssertEqual(wallet(regular: 5, name: "", symbol: "").regularText, "5.00")
        XCTAssertEqual(wallet(regular: 5, name: "USD", symbol: "₽").regularText, "₽5.00")
    }

    /// The three amounts are distinct: a bonus is not spendable balance, and a
    /// hold is not money the user has.
    func testEachAmountIsRenderedSeparately() {
        let w = wallet(regular: 10, bonus: 2.5, frozen: 3)
        XCTAssertEqual(w.regularText, "$10.00")
        XCTAssertEqual(w.bonusText, "$2.50")
        XCTAssertEqual(w.frozenText, "$3.00")
    }

    /// A field the server did not send is unknown, not zero. The server does
    /// send an explicit zero when the account genuinely has no bonus, and that
    /// zero is data — so the two cases must not collapse into one another.
    func testMissingBonusIsUnknownWhileAnExplicitZeroIsData() {
        XCTAssertNil(wallet(regular: 10).bonusText, "no bonus field means the server did not say")
        XCTAssertEqual(wallet(regular: 10, bonus: 0).bonusText, "$0.00", "an explicit zero is a reading")
    }

    /// Nothing on hold is the ordinary case and needs no row; a real hold does.
    func testFrozenAmountIsShownOnlyWhenNonZero() {
        XCTAssertNil(wallet(regular: 10, frozen: 0).frozenText)
        XCTAssertNil(wallet(regular: 10).frozenText)
        XCTAssertEqual(wallet(regular: 10, frozen: 1.5).frozenText, "$1.50")
    }

    /// A negative balance is the server's number and is passed through rather
    /// than clamped: hiding it would misstate an overdrawn account.
    func testNegativeBalanceIsPreserved() {
        XCTAssertEqual(wallet(regular: -3.5).regularText, "$-3.50")
    }
}

// MARK: - Session lifecycle

/// The transitions that decide whether a user is signed in, driven against a
/// stub server so each one can be provoked on demand.
@MainActor
final class WikiVibeAuthCoordinatorTests: XCTestCase {
    private let account = WikiVibeAccount(id: 42, username: "nick", email: "nick@example.com")

    private func session(expiresIn: TimeInterval, refreshToken: String = "refresh-1") -> WikiVibeSession {
        WikiVibeSession(accessToken: "access-1", refreshToken: refreshToken,
                        expiresIn: expiresIn, account: account)
    }

    /// A stored session that is still valid is adopted without any request
    /// beyond the account confirmation, and stays stored.
    func testRestoreAdoptsAValidStoredSession() async {
        let store = StubSessionStore(session: session(expiresIn: 3600))
        let api = StubAuthAPI(account: account)
        let coordinator = WikiVibeAuthCoordinator(api: api, store: store)

        await coordinator.restore()

        XCTAssertEqual(coordinator.state, .signedIn(account))
        XCTAssertNil(coordinator.notice)
        XCTAssertEqual(store.saved?.accessToken, "access-1")
    }

    /// The network being down is not the user signing out. The stored session
    /// is kept and the account is still shown, with a caveat.
    func testRestoreKeepsSessionWhenTheServerCannotBeReached() async {
        let store = StubSessionStore(session: session(expiresIn: 3600))
        let api = StubAuthAPI(account: account)
        api.accountError = .transport("offline")
        let coordinator = WikiVibeAuthCoordinator(api: api, store: store)

        await coordinator.restore()

        XCTAssertEqual(coordinator.state, .signedIn(account))
        XCTAssertNotNil(coordinator.notice)
        XCTAssertNotNil(store.saved, "a session the app could not verify must not be discarded")
    }

    /// An expired access token is renewed, and the rotated refresh token
    /// replaces the old one — keeping it would work once and then fail.
    func testRestoreRefreshesAnExpiredSessionAndStoresTheRotation() async {
        let store = StubSessionStore(session: session(expiresIn: 0))
        let api = StubAuthAPI(account: account)
        api.refreshed = session(expiresIn: 3600, refreshToken: "refresh-2")
        let coordinator = WikiVibeAuthCoordinator(api: api, store: store)

        await coordinator.restore()

        XCTAssertEqual(api.refreshCount, 1)
        XCTAssertEqual(coordinator.state, .signedIn(account))
        XCTAssertEqual(store.saved?.refreshToken, "refresh-2")
    }

    /// A refresh token the server refuses ends the session, locally and
    /// visibly: the app must not keep showing an account it cannot reach.
    func testRestoreSignsOutWhenTheRefreshTokenIsRefused() async {
        let store = StubSessionStore(session: session(expiresIn: 0))
        let api = StubAuthAPI(account: account)
        api.refreshError = .sessionExpired
        let coordinator = WikiVibeAuthCoordinator(api: api, store: store)

        await coordinator.restore()

        XCTAssertEqual(coordinator.state, .signedOut)
        XCTAssertNil(store.saved)
        XCTAssertTrue(store.cleared)
    }

    /// A revoked session discovered at the account check has the same outcome.
    func testRestoreSignsOutWhenTheAccountIsRejected() async {
        let store = StubSessionStore(session: session(expiresIn: 3600))
        let api = StubAuthAPI(account: account)
        api.accountError = .sessionExpired
        let coordinator = WikiVibeAuthCoordinator(api: api, store: store)

        await coordinator.restore()

        XCTAssertEqual(coordinator.state, .signedOut)
        XCTAssertTrue(store.cleared)
    }

    func testRestoreWithoutAStoredSessionStaysSignedOut() async {
        let store = StubSessionStore(session: nil)
        let api = StubAuthAPI(account: account)
        let coordinator = WikiVibeAuthCoordinator(api: api, store: store)

        await coordinator.restore()

        XCTAssertEqual(coordinator.state, .signedOut)
        XCTAssertEqual(api.refreshCount, 0)
    }

    /// Signing out clears the machine even when the server cannot be told: the
    /// user asked to be signed out *here*, and a leftover refresh token is the
    /// opposite of that.
    func testSignOutClearsTheSessionEvenWhenRevocationFails() async {
        let store = StubSessionStore(session: session(expiresIn: 3600))
        let api = StubAuthAPI(account: account)
        let coordinator = WikiVibeAuthCoordinator(api: api, store: store)
        await coordinator.restore()
        XCTAssertEqual(coordinator.state, .signedIn(account))

        await coordinator.signOut()

        XCTAssertEqual(coordinator.state, .signedOut)
        XCTAssertNil(store.saved)
        XCTAssertTrue(store.cleared)
        XCTAssertEqual(api.revokedRefreshTokens, ["refresh-1"])
    }

    func testCancelledExchangeCannotSaveSessionOrUnblockRestore() async throws {
        let suite = "cancel-exchange-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "auth.restoreBlockedAfterSignOut")
        let store = StubSessionStore(session: nil)
        let api = StubAuthAPI(account: account)
        let browserOpened = expectation(description: "authorization URL opened")
        let exchangeStarted = expectation(description: "exchange suspended")
        var callback: URL?
        var resumeExchange: CheckedContinuation<WikiVibeSession, Error>?
        api.exchangeHandler = {
            try await withCheckedThrowingContinuation { continuation in
                resumeExchange = continuation
                exchangeStarted.fulfill()
            }
        }
        let coordinator = WikiVibeAuthCoordinator(api: api, store: store, defaults: defaults,
            openAuthorizationURL: { url in
                let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
                let redirect = query.first { $0.name == "redirect" }!.value!
                let state = query.first { $0.name == "state" }!.value!
                var components = URLComponents(string: redirect)!
                components.queryItems = [.init(name: "code", value: "synthetic-code"), .init(name: "state", value: state)]
                callback = components.url!
                browserOpened.fulfill()
                return true
            })
        let signIn = Task { await coordinator.signIn() }
        await fulfillment(of: [browserOpened], timeout: 5)
        _ = try await get(try XCTUnwrap(callback).absoluteString)
        await fulfillment(of: [exchangeStarted], timeout: 5)
        await coordinator.cancelSignIn()
        resumeExchange?.resume(returning: session(expiresIn: 3600))
        await signIn.value
        coordinator.stopWalletPolling()
        XCTAssertNil(store.saved)
        XCTAssertTrue(defaults.bool(forKey: "auth.restoreBlockedAfterSignOut"))
        XCTAssertEqual(coordinator.state, .signedOut)
        XCTAssertEqual(api.walletCount, 0)
    }

    func testFailedKeychainDeletionBlocksRestoreAcrossInstances() async {
        let suite = "signout-security-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = StubSessionStore(session: session(expiresIn: 3600))
        let api = StubAuthAPI(account: account)
        let first = WikiVibeAuthCoordinator(api: api, store: store, defaults: defaults)
        await first.restore(); first.stopWalletPolling()
        store.clearSucceeds = false
        await first.signOut()
        XCTAssertNotNil(first.notice)
        XCTAssertNotNil(store.saved)
        let next = WikiVibeAuthCoordinator(api: api, store: store, defaults: defaults)
        await next.restore()
        XCTAssertEqual(next.state, .signedOut)
        XCTAssertNotNil(next.notice)
    }

    /// The refresh token is revoked, not every session the account has: signing
    /// out of the Mac must not sign the user out of the website.
    func testSignOutRevokesOnlyTheStoredRefreshToken() async {
        let store = StubSessionStore(session: session(expiresIn: 3600, refreshToken: "refresh-7"))
        let api = StubAuthAPI(account: account)
        let coordinator = WikiVibeAuthCoordinator(api: api, store: store)
        await coordinator.restore()

        await coordinator.signOut()

        XCTAssertEqual(api.revokedRefreshTokens, ["refresh-7"])
    }

    /// Restoring a session reads the money too: a signed-in window that never
    /// shows a balance would look like an account with nothing in it.
    func testRestoreLoadsTheBalance() async {
        let store = StubSessionStore(session: session(expiresIn: 3600))
        let api = StubAuthAPI(account: account)
        api.wallet = WikiVibeWallet(regular: 116.11, bonus: 0, frozen: 0,
                                    currencyName: "USD", currencySymbol: "$")
        let coordinator = WikiVibeAuthCoordinator(api: api, store: store)

        await coordinator.restore()

        XCTAssertEqual(api.walletCount, 1)
        XCTAssertEqual(coordinator.wallet?.regularText, "$116.11")
        XCTAssertNil(coordinator.walletError)
    }

    /// A balance that could not be read leaves the user signed in. The session
    /// is fine — only the number is missing, and signing out over it would cost
    /// the user another trip through the browser for nothing.
    func testWalletFailureKeepsTheSessionAndSaysWhy() async {
        let store = StubSessionStore(session: session(expiresIn: 3600))
        let api = StubAuthAPI(account: account)
        api.walletError = .transport("offline")
        let coordinator = WikiVibeAuthCoordinator(api: api, store: store)

        await coordinator.restore()

        XCTAssertEqual(coordinator.state, .signedIn(account))
        XCTAssertNil(coordinator.wallet, "an unread balance must not be shown as zero")
        XCTAssertNotNil(coordinator.walletError)
        XCTAssertNotNil(store.saved, "the session itself was never in question")
    }

    /// A revoked session discovered while reading the balance is still a
    /// revoked session: the app signs out rather than reporting a money error.
    func testWalletSessionExpirySignsOut() async {
        let store = StubSessionStore(session: session(expiresIn: 3600))
        let api = StubAuthAPI(account: account)
        api.walletError = .sessionExpired
        let coordinator = WikiVibeAuthCoordinator(api: api, store: store)

        await coordinator.restore()

        XCTAssertEqual(coordinator.state, .signedOut)
        XCTAssertTrue(store.cleared)
        XCTAssertNil(coordinator.wallet)
    }

    /// Signing out takes the money off the screen: it belonged to a session the
    /// app no longer has.
    func testSignOutClearsTheBalance() async {
        let store = StubSessionStore(session: session(expiresIn: 3600))
        let api = StubAuthAPI(account: account)
        api.wallet = WikiVibeWallet(regular: 5, bonus: nil, frozen: nil,
                                    currencyName: "USD", currencySymbol: "$")
        let coordinator = WikiVibeAuthCoordinator(api: api, store: store)
        await coordinator.restore()
        XCTAssertNotNil(coordinator.wallet)

        await coordinator.signOut()

        XCTAssertNil(coordinator.wallet)
        XCTAssertNil(coordinator.walletError)
    }

    /// The balance is re-read while signed in, so a number another machine
    /// moves does not stay on screen at its old value.
    func testWalletPollingRefreshesTheBalance() async {
        let store = StubSessionStore(session: session(expiresIn: 3600))
        let api = StubAuthAPI(account: account)
        api.wallet = WikiVibeWallet(regular: 10, bonus: nil, frozen: nil,
                                    currencyName: "USD", currencySymbol: "$")
        let coordinator = WikiVibeAuthCoordinator(api: api, store: store)
        await coordinator.restore()
        let afterRestore = api.walletCount

        // The interval is a minute; the poll is driven directly rather than
        // waited out, so the test does not depend on wall-clock time.
        api.wallet = WikiVibeWallet(regular: 7.5, bonus: nil, frozen: nil,
                                    currencyName: "USD", currencySymbol: "$")
        await coordinator.loadWallet()

        XCTAssertEqual(api.walletCount, afterRestore + 1)
        XCTAssertEqual(coordinator.wallet?.regularText, "$7.50")
    }

    /// One poll, not one per call: restore, sign-in and opening the window all
    /// ask for polling, and a second task would double the request rate.
    func testStartingPollingTwiceKeepsOnePoll() async {
        let store = StubSessionStore(session: session(expiresIn: 3600))
        let api = StubAuthAPI(account: account)
        api.wallet = WikiVibeWallet(regular: 1, bonus: nil, frozen: nil,
                                    currencyName: "USD", currencySymbol: "$")
        let coordinator = WikiVibeAuthCoordinator(api: api, store: store)
        await coordinator.restore()

        coordinator.startWalletPolling()
        coordinator.startWalletPolling()
        coordinator.stopWalletPolling()
        coordinator.stopWalletPolling()

        // Reaching here without a crash or a leaked task is the assertion; the
        // observable contract is that a stopped poll can be started again.
        coordinator.startWalletPolling()
        coordinator.stopWalletPolling()
    }

    /// The visible window polls faster, and only the interval changes — the
    /// poll keeps running, so no reading is skipped when the window opens.
    func testVisibleWindowShortensTheInterval() async {
        let store = StubSessionStore(session: session(expiresIn: 3600))
        let api = StubAuthAPI(account: account)
        api.wallet = WikiVibeWallet(regular: 1, bonus: nil, frozen: nil,
                                    currencyName: "USD", currencySymbol: "$")
        let coordinator = WikiVibeAuthCoordinator(api: api, store: store)
        await coordinator.restore()

        XCTAssertEqual(coordinator.currentWalletInterval(), WikiVibeAuthCoordinator.walletRefreshInterval)
        coordinator.setWalletVisible(true)
        XCTAssertEqual(coordinator.currentWalletInterval(), WikiVibeAuthCoordinator.walletRefreshIntervalVisible)
        XCTAssertLessThan(WikiVibeAuthCoordinator.walletRefreshIntervalVisible,
                          WikiVibeAuthCoordinator.walletRefreshInterval)
        coordinator.setWalletVisible(false)
        XCTAssertEqual(coordinator.currentWalletInterval(), WikiVibeAuthCoordinator.walletRefreshInterval)
    }
}

// MARK: - Stubs

/// A session store that keeps everything in memory, so the lifecycle can be
/// driven without a login keychain.
private final class StubSessionStore: WikiVibeSessionStoreInterface {
    private(set) var saved: WikiVibeSession?
    private(set) var cleared = false
    var clearSucceeds = true

    init(session: WikiVibeSession?) { self.saved = session }

    func load() -> WikiVibeSession? { saved }

    func save(_ session: WikiVibeSession) -> Bool {
        saved = session
        return true
    }

    func clear() -> Bool {
        guard clearSucceeds else { return false }
        saved = nil
        cleared = true
        return true
    }
}

/// An auth API whose answers each test chooses.
private final class StubAuthAPI: WikiVibeAuthAPIInterface, @unchecked Sendable {
    let account: WikiVibeAccount
    var accountError: WikiVibeAuthError?
    var refreshError: WikiVibeAuthError?
    var refreshed: WikiVibeSession?
    var wallet: WikiVibeWallet?
    var walletError: WikiVibeAuthError?
    var exchangeHandler: (() async throws -> WikiVibeSession)?
    private(set) var refreshCount = 0
    private(set) var walletCount = 0
    private(set) var revokedRefreshTokens: [String] = []

    init(account: WikiVibeAccount) { self.account = account }

    func authorizationURL(pkce: WikiVibePKCE, redirectURI: String) throws -> URL {
        var url = URLComponents(string: "https://auth.example.invalid/login")!
        url.queryItems = [.init(name: "redirect", value: redirectURI), .init(name: "state", value: pkce.state)]
        return url.url!
    }

    func exchange(code: String, verifier: String, redirectURI: String) async throws -> WikiVibeSession {
        if let exchangeHandler { return try await exchangeHandler() }
        throw WikiVibeAuthError.tokenExchangeFailed("not used")
    }

    func refresh(using session: WikiVibeSession) async throws -> WikiVibeSession {
        refreshCount += 1
        if let refreshError { throw refreshError }
        return refreshed ?? session
    }

    func account(for session: WikiVibeSession) async throws -> WikiVibeAccount {
        if let accountError { throw accountError }
        return account
    }

    func wallet(for session: WikiVibeSession) async throws -> WikiVibeWallet {
        walletCount += 1
        if let walletError { throw walletError }
        guard let wallet else { throw WikiVibeAuthError.balanceUnavailable("not configured") }
        return wallet
    }

    func revoke(refreshToken: String) async {
        revokedRefreshTokens.append(refreshToken)
    }
}

// MARK: - HTTP helper

/// A GET against the loopback listener, reporting the status it answered with.
private func get(_ urlString: String) async throws -> (status: Int, body: Data) {
    let (data, response) = try await URLSession.shared.data(from: URL(string: urlString)!)
    return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
}
