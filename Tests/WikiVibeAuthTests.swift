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
            .malformed("missing state")
        )
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
        XCTAssertEqual(WikiVibeCallbackQuery.parse(uri: "/callback", expectedState: state), .malformed("missing state"))
        XCTAssertEqual(
            WikiVibeCallbackQuery.parse(uri: "/callback?code=&state=\(state)", expectedState: state),
            .malformed("missing code")
        )
        // A path that merely starts with the callback path is a different path.
        XCTAssertEqual(WikiVibeCallbackQuery.parse(uri: "/callback/extra", expectedState: state), .notFound)
    }

    func testUnparseableTargetIsMalformed() {
        XCTAssertEqual(
            WikiVibeCallbackQuery.parse(uri: "http://[::1", expectedState: state),
            .malformed("unparseable request target")
        )
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
        XCTAssertEqual(try await outcome, .authorized(code: "code-1"))
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
        XCTAssertEqual(try await outcome, .authorized(code: "code-2"))
    }

    func testListenerGivesUpAfterTheDeadline() async throws {
        let server = try await WikiVibeCallbackServer.start(expectedState: state)
        defer { Task { await server.stop() } }
        XCTAssertEqual(try await server.waitForCallback(timeout: 1), .timedOut)
    }

    /// Closing the listener must release the wait, or a cancelled sign-in would
    /// leave the app waiting for a callback that can no longer arrive.
    func testStoppingTheListenerCancelsTheWait() async throws {
        let server = try await WikiVibeCallbackServer.start(expectedState: state)
        async let outcome = server.waitForCallback(timeout: 30)
        await server.stop()
        XCTAssertEqual(try await outcome, .cancelled)
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
}

// MARK: - Stubs

/// A session store that keeps everything in memory, so the lifecycle can be
/// driven without a login keychain.
private final class StubSessionStore: WikiVibeSessionStoreInterface {
    private(set) var saved: WikiVibeSession?
    private(set) var cleared = false

    init(session: WikiVibeSession?) { self.saved = session }

    func load() -> WikiVibeSession? { saved }

    func save(_ session: WikiVibeSession) -> Bool {
        saved = session
        return true
    }

    func clear() -> Bool {
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
    private(set) var refreshCount = 0
    private(set) var revokedRefreshTokens: [String] = []

    init(account: WikiVibeAccount) { self.account = account }

    func authorizationURL(pkce: WikiVibePKCE, redirectURI: String) throws -> URL {
        URL(string: "https://auth.wikivibe.dev/login?redirect=\(redirectURI)")!
    }

    func exchange(code: String, verifier: String, redirectURI: String) async throws -> WikiVibeSession {
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
