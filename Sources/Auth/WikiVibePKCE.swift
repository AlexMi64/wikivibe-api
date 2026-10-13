import CryptoKit
import Foundation

/// The PKCE half of the authorization request (RFC 7636, S256).
///
/// A public client has no secret, so the only thing that makes a stolen code
/// useless is the verifier: it is generated here, sent to the browser only as a
/// SHA-256 digest, and presented back to the token endpoint from this process.
/// Anything that sees the redirect — a screenshot, a browser history entry,
/// another app polling loopback — gets a code it cannot spend.
struct WikiVibePKCE: Equatable {
    /// Sent to `/authorize` as `code_challenge`. Safe to appear in a URL.
    let challenge: String
    /// Kept in memory until the token exchange, never logged or persisted.
    let verifier: String
    /// Round-tripped through the browser so a callback for a different attempt
    /// cannot be mistaken for this one.
    let state: String

    init(verifier: String, state: String) {
        self.verifier = verifier
        self.state = state
        self.challenge = WikiVibePKCE.challenge(for: verifier)
    }

    /// A fresh verifier and state from the system CSPRNG.
    ///
    /// The entropy source is `SecRandomCopyBytes` rather than
    /// `UInt8.random(in:)`: the latter is only as strong as the generator the
    /// standard library happens to use, and "the verifier is unguessable" is
    /// the entire security argument for a public client. A failure here is
    /// reported rather than papered over with a weaker source — a sign-in that
    /// cannot produce unpredictable PKCE material must not proceed.
    static func generate() throws -> WikiVibePKCE {
        WikiVibePKCE(verifier: base64URL(try randomBytes(count: 64)),
                     state: base64URL(try randomBytes(count: 24)))
    }

    /// base64url without padding, per RFC 7636 §4.2 and the server's validator.
    ///
    /// The alphabet (`A-Z a-z 0-9 - _`) sits inside the unreserved set the
    /// server accepts for a verifier and inside the visible ASCII it accepts
    /// for a state, so neither needs escaping in the authorization URL.
    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func randomBytes(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else { throw WikiVibeAuthError.entropyUnavailable }
        return Data(bytes)
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
