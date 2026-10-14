import Foundation

/// The server half of sign-in, as the coordinator uses it.
///
/// A protocol so the session lifecycle — restore, expired refresh, sign-out
/// with an unreachable server — can be exercised without a live account: those
/// transitions are the ones that decide whether a user is signed out, and none
/// of them can be provoked reliably against the real server.
protocol WikiVibeAuthAPIInterface: Sendable {
    func authorizationURL(pkce: WikiVibePKCE, redirectURI: String) throws -> URL
    func exchange(code: String, verifier: String, redirectURI: String) async throws -> WikiVibeSession
    func refresh(using session: WikiVibeSession) async throws -> WikiVibeSession
    func account(for session: WikiVibeSession) async throws -> WikiVibeAccount
    func wallet(for session: WikiVibeSession) async throws -> WikiVibeWallet
    func revoke(refreshToken: String) async
}

/// The server half of sign-in: build the authorization URL, exchange the code,
/// renew the session, read the account, end it.
///
/// Nothing here decides *when* to do any of that — that is
/// `WikiVibeAuthCoordinator`. This type is the only place that knows the wire
/// format, so the envelope and its error field are handled once.
struct WikiVibeAuthAPI: WikiVibeAuthAPIInterface {
    /// Every panel response is wrapped, and the wrapper is authoritative:
    /// `response.Success` reports business failures with HTTP 200 and a
    /// non-zero `code`, so trusting the status line alone would read a refusal
    /// as a success with missing fields.
    private struct Envelope<Payload: Decodable>: Decodable {
        let code: Int
        let message: String?
        let reason: String?
        let data: Payload?
    }

    private struct TokenPayload: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Int?
        let user: User

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case user
        }
    }

    private struct RefreshPayload: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Int?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
        }
    }

    private struct MePayload: Decodable {
        let user: User
    }

    /// `/user/profile`. Only the money fields are declared: the response carries
    /// much more (identity bindings, notification settings), and decoding fields
    /// the app never shows would mean holding them in memory for no reason.
    private struct ProfilePayload: Decodable {
        let balance: Double?
        let bonusBalance: Double?
        let frozenBalance: Double?

        enum CodingKeys: String, CodingKey {
            case balance
            case bonusBalance = "bonus_balance"
            case frozenBalance = "frozen_balance"
        }
    }

    /// `/settings/public`. The unit is an operator setting, not a constant.
    private struct PublicSettingsPayload: Decodable {
        let balanceUnitName: String?
        let balanceUnitSymbol: String?

        enum CodingKeys: String, CodingKey {
            case balanceUnitName = "balance_unit_name"
            case balanceUnitSymbol = "balance_unit_symbol"
        }
    }

    private struct User: Decodable {
        let id: Int
        let username: String?
        let email: String?
    }

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
            return
        }
        // Ephemeral on purpose: the app authenticates with a bearer token, so
        // there is no cookie to keep, and a cache of account responses on disk
        // is exactly what a signed-out app must not leave behind.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
    }

    // MARK: - Authorization URL

    /// The URL the system browser is sent to.
    ///
    /// The redirect URI carries the loopback port the listener actually got, so
    /// it is built here rather than stored. `response_type` and `grant_type`
    /// are absent on purpose: this server's browser flow does not use them, and
    /// sending parameters it does not read invites the belief that it does.
    func authorizationURL(pkce: WikiVibePKCE, redirectURI: String) throws -> URL {
        guard var components = URLComponents(
            url: WikiVibeAuthContract.issuer.appendingPathComponent(WikiVibeAuthContract.authorizePath),
            resolvingAgainstBaseURL: false
        ) else {
            throw WikiVibeAuthError.invalidAuthorizationRequest("authorize URL is not a URL")
        }
        components.queryItems = [
            URLQueryItem(name: "client_id", value: WikiVibeAuthContract.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "state", value: pkce.state),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        guard let url = components.url else {
            throw WikiVibeAuthError.invalidAuthorizationRequest("authorize URL could not be assembled")
        }
        return url
    }

    // MARK: - Token exchange

    func exchange(code: String, verifier: String, redirectURI: String) async throws -> WikiVibeSession {
        let payload: TokenPayload = try await post(
            path: WikiVibeAuthContract.tokenPath,
            body: [
                "client_id": WikiVibeAuthContract.clientID,
                "redirect_uri": redirectURI,
                "code": code,
                "code_verifier": verifier
            ]
        )
        // A refresh token is what makes the session survive its access token.
        // Without one the sign-in would look complete and then fail an hour
        // later with no way back, so it is required rather than defaulted.
        guard let refreshToken = payload.refreshToken, !refreshToken.isEmpty else {
            throw WikiVibeAuthError.tokenExchangeFailed("the server issued no refresh token")
        }
        return WikiVibeSession(
            accessToken: payload.accessToken,
            refreshToken: refreshToken,
            expiresIn: TimeInterval(payload.expiresIn ?? Int(WikiVibeAuthContract.fallbackAccessTokenLifetime)),
            account: Self.account(from: payload.user)
        )
    }

    /// Renew an expired access token.
    ///
    /// The refresh token is replaced by whatever the server returns, because
    /// this endpoint rotates: keeping the old one would work once and then fail
    /// with a revoked token, which reads as "signed out" for no reason the user
    /// can see.
    func refresh(using session: WikiVibeSession) async throws -> WikiVibeSession {
        let payload: RefreshPayload
        do {
            payload = try await post(
                path: WikiVibeAuthContract.refreshPath,
                body: [
                    "client_id": WikiVibeAuthContract.clientID,
                    "refresh_token": session.refreshToken
                ]
            )
        } catch let error as WikiVibeAuthError {
            // The refresh token itself was refused: this session is over, and
            // the app must say so rather than retry with the same dead token.
            throw error
        }
        return WikiVibeSession(
            accessToken: payload.accessToken,
            refreshToken: payload.refreshToken.flatMap { $0.isEmpty ? nil : $0 } ?? session.refreshToken,
            expiresIn: TimeInterval(payload.expiresIn ?? Int(WikiVibeAuthContract.fallbackAccessTokenLifetime)),
            account: session.account
        )
    }

    // MARK: - Account

    /// The account's money, in the server's own unit.
    ///
    /// Two calls, because the amount and its unit come from different places:
    /// `/user/profile` needs the session, `/settings/public` does not. The unit
    /// is fetched first so a balance is never rendered in a guessed currency,
    /// and a missing `balance` is reported rather than read as zero — the
    /// account has money; the app simply did not get it.
    func wallet(for session: WikiVibeSession) async throws -> WikiVibeWallet {
        let settings: PublicSettingsPayload = try await get(
            path: WikiVibeAuthContract.publicSettingsPath,
            token: nil
        )
        let profile: ProfilePayload = try await get(
            path: WikiVibeAuthContract.profilePath,
            token: session.accessToken
        )
        guard let balance = profile.balance else {
            throw WikiVibeAuthError.balanceUnavailable("the server reported no balance")
        }
        return WikiVibeWallet(
            regular: balance,
            bonus: profile.bonusBalance,
            frozen: profile.frozenBalance,
            currencyName: settings.balanceUnitName ?? "",
            currencySymbol: settings.balanceUnitSymbol ?? ""
        )
    }

    /// Confirm the account a session belongs to.
    ///
    /// Used after restore, where the only local evidence is a keychain item:
    /// the account name shown must come from the server, not from whatever the
    /// stored copy says, or a revoked session would keep displaying an account.
    func account(for session: WikiVibeSession) async throws -> WikiVibeAccount {
        let payload: MePayload = try await get(
            path: WikiVibeAuthContract.accountPath,
            token: session.accessToken
        )
        return Self.account(from: payload.user)
    }

    /// End the session on the server. Best effort: the local session is cleared
    /// either way, because a network failure must not leave a user signed in on
    /// a machine they told the app to sign out of.
    func revoke(refreshToken: String) async {
        _ = try? await postRaw(
            path: WikiVibeAuthContract.logoutPath,
            body: ["refresh_token": refreshToken],
            token: nil
        )
    }

    // MARK: - Transport

    private func get<Payload: Decodable>(path: String, token: String?) async throws -> Payload {
        var request = URLRequest(url: WikiVibeAuthContract.api.appendingPathComponent(path))
        request.httpMethod = "GET"
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await send(request)
    }

    private func post<Payload: Decodable>(path: String, body: [String: String]) async throws -> Payload {
        try await send(try request(path: path, body: body, token: nil))
    }

    @discardableResult
    private func postRaw(path: String, body: [String: String], token: String?) async throws -> Data {
        let request = try request(path: path, body: body, token: token)
        let (data, _) = try await session.data(for: request)
        return data
    }

    private func request(path: String, body: [String: String], token: String?) throws -> URLRequest {
        var request = URLRequest(url: WikiVibeAuthContract.api.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private func send<Payload: Decodable>(_ request: URLRequest) async throws -> Payload {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw WikiVibeAuthError.transport(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // A 401/403 need not use the success payload or its numeric code type.
        if status == 401 || status == 403 {
            throw WikiVibeAuthError.sessionExpired
        }
        guard let envelope = try? JSONDecoder().decode(Envelope<Payload>.self, from: data) else {
            throw WikiVibeAuthError.transport("unreadable response (HTTP \(status))")
        }
        // The wrapper decides, not the status line: a business failure arrives
        // as HTTP 200 with a non-zero code.
        guard envelope.code == 0, let payload = envelope.data else {
            throw Self.failure(status: status, envelope: envelope)
        }
        return payload
    }

    /// Turn a refusal into the app's own error, keeping the server's words.
    private static func failure<Payload: Decodable>(status: Int,
                                                    envelope: Envelope<Payload>) -> WikiVibeAuthError {
        let reason = [envelope.reason, envelope.message]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "HTTP \(status)"
        // 401/403 from the account or refresh endpoints means the credential is
        // gone, not that the request was malformed — the difference decides
        // whether the app offers sign-in again or reports a failure.
        if status == 401 || status == 403 {
            return .sessionExpired
        }
        return status >= 400 ? .tokenExchangeFailed(reason) : .transport(reason)
    }

    private static func account(from user: User) -> WikiVibeAccount {
        WikiVibeAccount(
            id: user.id,
            username: user.username ?? "",
            email: user.email ?? ""
        )
    }
}
