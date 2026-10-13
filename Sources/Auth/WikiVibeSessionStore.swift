import Foundation

/// Where the signed-in session lives between launches.
///
/// A refresh token is a long-lived credential to the user's WikiVibe account,
/// so it goes in the login keychain — the same place, and through the same
/// helper, as every other secret this app holds. Not `UserDefaults`, which is
/// a plain file any process running as the user can read, and not the web view
/// store, which the app cannot audit.
///
/// The whole session is one keychain item, JSON-encoded. Splitting the tokens
/// and the account across items would allow a state where one is written and
/// the other is not, and a session that is half-restored is worse than none:
/// it looks signed in and cannot make a request.
enum WikiVibeSessionStore {
    static let keychainService = "wikivibe-desktop-session"
    static let keychainAccount = "wikivibe"

    /// Read the stored session, or nil when there is none or it cannot be read.
    ///
    /// A failure to read is *not* a signed-out state: the keychain can be
    /// locked, or the item can belong to a different build identity. Callers
    /// get nil and decide; the app does not silently delete a session because
    /// it could not be opened.
    static func load() -> WikiVibeSession? {
        guard let raw = KeychainItem.read(service: keychainService, account: keychainAccount),
              let data = raw.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(WikiVibeSession.self, from: data)
    }

    /// Whether a session item exists at all, without reading its secret.
    ///
    /// Reading an own item normally does not prompt, but the *first* read after
    /// a rebuild with a new signing identity can, and the app asks this on
    /// launch to decide what to show. Enumeration never prompts.
    static var hasStoredSession: Bool {
        KeychainItem.modifiedAt(service: keychainService, account: keychainAccount) != nil
    }

    @discardableResult
    static func save(_ session: WikiVibeSession) -> Bool {
        guard let data = try? JSONEncoder().encode(session),
              let raw = String(data: data, encoding: .utf8)
        else { return false }
        return KeychainItem.store(service: keychainService, account: keychainAccount, value: raw)
    }

    @discardableResult
    static func clear() -> Bool {
        KeychainItem.delete(service: keychainService, account: keychainAccount)
    }
}
