import Foundation

/// Everything that can go wrong between "Sign in" and a stored session.
///
/// Each case carries the server's own words where there are any: a user who is
/// told `invalid_grant` can search for it, while "something went wrong" tells
/// them nothing and tells whoever reads the log less.
enum WikiVibeAuthError: LocalizedError, Equatable {
    /// The authorization URL could not be built from the registered values.
    case invalidAuthorizationRequest(String)
    /// The system browser refused to open the URL.
    case browserDidNotOpen
    /// The OS would not give the app a loopback port.
    case couldNotListen(String)
    /// The server returned a code, but the exchange was refused.
    case tokenExchangeFailed(String)
    /// A stored session is no longer accepted and could not be renewed.
    case sessionExpired
    /// The server did not answer, or answered with something unusable.
    case transport(String)
    /// `SecRandomCopyBytes` failed, so PKCE material cannot be trusted.
    case entropyUnavailable
    /// The session was obtained but could not be written to the keychain.
    case storageFailed
    /// The account's money could not be read. Not zero — unknown.
    case balanceUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidAuthorizationRequest(let reason):
            return L10n.t("The sign-in request could not be built: \(reason)")
        case .browserDidNotOpen:
            return L10n.t("The system browser could not be opened.")
        case .couldNotListen(let reason):
            return L10n.t("The sign-in listener could not start: \(reason)")
        case .tokenExchangeFailed(let reason):
            return L10n.t("WikiVibe refused the sign-in: \(reason)")
        case .sessionExpired:
            return L10n.t("The session has expired. Sign in again.")
        case .transport(let reason):
            return L10n.t("The sign-in service could not be reached: \(reason)")
        case .entropyUnavailable:
            return L10n.t("A secure sign-in request could not be generated.")
        case .storageFailed:
            return L10n.t("The session could not be saved to the keychain.")
        case .balanceUnavailable(let reason):
            return L10n.t("The balance could not be read: \(reason)")
        }
    }
}

/// A signed-in account, as far as the app is allowed to know it.
///
/// Deliberately not the full profile: the app shows who is signed in, and the
/// only fields kept are the ones that answer that. Anything else the API
/// returns is not stored, so it cannot leak from a file the app writes.
struct WikiVibeAccount: Codable, Equatable {
    let id: Int
    let username: String
    let email: String

    var displayName: String {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? email : name
    }
}

/// The token pair the server issued, with the expiry resolved to a moment in
/// time rather than a duration.
///
/// `expiresIn` is seconds from the moment the response was received, so keeping
/// it as a number would make the value mean something different every time it
/// was read. Absolute dates also survive a restart, which is when the app most
/// needs to know whether it can still use what it stored.
struct WikiVibeSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let account: WikiVibeAccount

    /// Treat the token as spent slightly early. A request that leaves just
    /// before expiry and lands just after is the one that gets a 401, and the
    /// clock here is not the server's.
    private static let earlyExpiry: TimeInterval = 30

    var isExpired: Bool { Date() >= expiresAt.addingTimeInterval(-Self.earlyExpiry) }

    init(accessToken: String, refreshToken: String, expiresIn: TimeInterval, account: WikiVibeAccount) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = Date().addingTimeInterval(max(expiresIn, 0))
        self.account = account
    }
}
