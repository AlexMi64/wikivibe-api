import Foundation

/// The registered OAuth client this app *is*, and the endpoints it may call.
///
/// Every value here is a server-side decision, not a client preference: the
/// backend accepts exactly the `client_id`/`redirect_uri` pair it registered
/// and rejects everything else at the authorize step. Editing a path here does
/// not widen the app's access — it makes sign-in fail with `INVALID_REQUEST`,
/// which is the honest outcome. The desktop client is registered as a public
/// client (no secret ships in the binary) and its callback is a loopback
/// address on the user's own machine.
///
/// `desktop` is registered *without* a port: the app asks the OS for a free
/// one, because a fixed port would collide with whatever else already holds it
/// and sign-in would break for reasons the user cannot see. The server accepts
/// any port for the registered scheme, host and path, and the code is bound to
/// a PKCE verifier that never leaves this process.
enum WikiVibeAuthContract {
    /// Public client id registered for the macOS app.
    static let clientID = "desktop"

    /// Where the browser signs in and where the code is issued.
    static let issuer = URL(string: "https://auth.wikivibe.dev")!
    /// The API host that exchanges the code and serves the account.
    static let api = URL(string: "https://api.wikivibe.dev")!

    static let authorizePath = "/api/v1/auth/sso/authorize"
    static let tokenPath = "/api/v1/auth/sso/token"
    static let refreshPath = "/api/v1/auth/refresh"
    static let logoutPath = "/api/v1/auth/logout"
    static let accountPath = "/api/v1/auth/sso/me"

    /// The registered loopback callback. Host and path are fixed by the
    /// server's validation; only the port is chosen at runtime.
    static let callbackHost = "127.0.0.1"
    static let callbackPath = "/callback"

    static func redirectURI(port: Int) -> String {
        "http://\(callbackHost):\(port)\(callbackPath)"
    }

    /// Seconds the app treats an access token as valid, when the server did not
    /// say. Deliberately short: a wrong guess here means one extra refresh, not
    /// a request made with a token that has already expired.
    static let fallbackAccessTokenLifetime: TimeInterval = 300
}
