import Foundation

/// A panel key is not the OAuth credential used to read it. Values live only in
/// memory until an explicit agent configuration write; never in UserDefaults.
struct WikiVibeAccountKey: Decodable, Identifiable, CustomStringConvertible, CustomDebugStringConvertible {
    struct Group: Decodable {
        let name: String?
        let platform: String?
        let allowedClientProtocols: [String]?
        enum CodingKeys: String, CodingKey {
            case name, platform
            case allowedClientProtocols = "allowed_client_protocols"
        }
    }
    let id: Int
    let name: String
    let key: String?
    let status: String
    let expiresAt: Date?
    let teamOwnerDisabled: Bool?
    let routingMode: String?
    let group: Group?
    enum CodingKeys: String, CodingKey {
        case id, name, key, status, group
        case expiresAt = "expires_at"
        case teamOwnerDisabled = "team_owner_disabled"
        case routingMode = "routing_mode"
    }
    var displayName: String {
        guard let key, !key.isEmpty else { return name }
        return name.replacingOccurrences(of: key, with: "••••")
    }
    var isUsable: Bool {
        guard status == "active", teamOwnerDisabled != true,
              expiresAt.map({ $0 > Date() }) ?? true, let key, !key.isEmpty else { return false }
        return key.count <= 4096 && !key.contains(where: { $0.isWhitespace || $0.isASCII && $0.asciiValue! < 32 })
            && !key.contains("*") && !key.contains("•")
    }
    var protocols: [String]? {
        let configured = group?.allowedClientProtocols
        if routingMode == "auto", configured?.isEmpty != false {
            return ["anthropic_messages", "openai_responses", "openai_chat_completions"]
        }
        return configured
    }
    var description: String { "WikiVibeAccountKey(id: \(id), secret: redacted)" }
    var debugDescription: String { description }
}

enum WikiVibeGateway: String, CaseIterable, Identifiable, Codable {
    case primary = "https://api.wikivibe.dev/v1"
    case alternative = "https://vapi.wikivibe.dev/v1"
    var id: String { rawValue }
    var url: URL { URL(string: rawValue)! }
}

enum WikiVibeAgent: String, CaseIterable, Identifiable, Codable {
    case codex, omp, opencode, claude
    var id: String { rawValue }
    var title: String {
        switch self {
        case .codex: return "Codex"
        case .omp: return "oh-my-pi"
        case .opencode: return "OpenCode"
        case .claude: return "Claude Code"
        }
    }
    func supports(_ protocols: [String]?) -> Bool {
        guard let protocols else { return true } // Unknown is reported, not invented capability.
        switch self {
        case .codex: return protocols.contains("openai_responses")
        case .claude: return protocols.contains("anthropic_messages")
        case .omp, .opencode:
            return protocols.contains("openai_responses") || protocols.contains("openai_chat_completions")
        }
    }
}

enum WikiVibeKeysError: Error, LocalizedError {
    case notSignedIn, unauthorized, denied, keyDenied, network, unreadable, noModels, unusableKey
    case nodeMissing, adapterMissing, setupFailed, conflict, invalidConfiguration, unsafePath, locked
    var errorDescription: String? {
        switch self {
        case .notSignedIn, .unauthorized: return L10n.t("Sign in again to load API keys.")
        case .denied: return L10n.t("This account session cannot access API keys. Your sign-in has been kept.")
        case .keyDenied: return L10n.t("This API key was refused at the selected API address. Choose another key or address; account sign-in is unchanged.")
        case .network: return L10n.t("Could not reach WikiVibe. Try again when the connection is available.")
        case .unreadable: return L10n.t("WikiVibe returned an unreadable key or model list.")
        case .noModels: return L10n.t("This key has no available models at the selected API address.")
        case .unusableKey: return L10n.t("Choose an active key with its complete value and a compatible agent.")
        case .nodeMissing: return L10n.t("Install Node.js 22 or newer to configure agents. API keys can still be viewed here.")
        case .adapterMissing: return L10n.t("The bundled agent configuration adapter could not be opened.")
        case .setupFailed: return L10n.t("Agent setup did not finish. Review the file results before trying again.")
        case .conflict: return L10n.t("Agent settings changed or conflict with WikiVibe. Your edits were kept. Preview again or resolve the conflict manually.")
        case .invalidConfiguration: return L10n.t("The agent configuration is invalid or uses an unsupported format. It was not replaced.")
        case .unsafePath: return L10n.t("The configuration path or backup has unsafe permissions or links. No unsafe file was replaced.")
        case .locked: return L10n.t("Another setup is running, or a previous run left ~/.wikivibe-gateway.lock. Remove that lock only after checking that no setup process is active.")
        }
    }
}

protocol WikiVibeKeysAPIInterface: Sendable {
    func keys(accessToken: String) async throws -> [WikiVibeAccountKey]
}

struct WikiVibeModel: Hashable, Sendable {
    let id: String
    let type: String?
    let protocols: [String]?
}
/// No response body or upstream diagnostic is surfaced: it may contain a key.
final class WikiVibeKeysAPI: WikiVibeKeysAPIInterface, @unchecked Sendable {
    private let client: URLSession
    init(client: URLSession? = nil) {
        if let client { self.client = client; return }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        self.client = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }
    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
    private struct Envelope<T: Decodable>: Decodable { let code: Int; let data: T? }
    private struct Page: Decodable { let items: [WikiVibeAccountKey]; let pages: Int }
    private struct Models: Decodable {
        struct Item: Decodable { let id: String; let type: String?; let protocols: [String]? }
        let data: [Item]
    }
    func keys(accessToken: String) async throws -> [WikiVibeAccountKey] {
        var page = 1
        var result = [WikiVibeAccountKey]()
        var ids = Set<Int>()
        repeat {
            var url = URLComponents(url: WikiVibeAuthContract.api.appendingPathComponent("/api/v1/keys"), resolvingAgainstBaseURL: false)!
            url.queryItems = [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "page_size", value: "100")]
            let data = try await get(url.url!, bearer: accessToken, account: true)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let raw = try decoder.singleValueContainer().decode(String.self)
                let fractional = ISO8601DateFormatter()
                fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                guard let date = fractional.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) else {
                    throw WikiVibeKeysError.unreadable
                }
                return date
            }
            guard let envelope = try? decoder.decode(Envelope<Page>.self, from: data), envelope.code == 0,
                  let payload = envelope.data, (0...10_000).contains(payload.pages) else { throw WikiVibeKeysError.unreadable }
            result.append(contentsOf: payload.items.filter { ids.insert($0.id).inserted })
            if page >= payload.pages { return result }
            page += 1
        } while page <= 10_000
        throw WikiVibeKeysError.unreadable
    }
    func models(gateway: WikiVibeGateway, key: String) async throws -> [WikiVibeModel] {
        let data = try await get(gateway.url.appendingPathComponent("models"), bearer: key, account: false)
        guard let models = try? JSONDecoder().decode(Models.self, from: data) else { throw WikiVibeKeysError.unreadable }
        var result = [WikiVibeModel]()
        var ids = Set<String>()
        for item in models.data {
            guard !item.id.isEmpty, item.id.count <= 256, !item.id.contains(key),
                  !item.id.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw WikiVibeKeysError.unreadable }
            guard ids.insert(item.id).inserted else { continue }
            result.append(WikiVibeModel(id: item.id, type: item.type, protocols: item.protocols))
        }
        guard !result.isEmpty else { throw WikiVibeKeysError.noModels }
        return result.sorted { $0.id < $1.id }
    }
    private func get(_ url: URL, bearer: String, account: Bool) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data
        let response: URLResponse
        do { (data, response) = try await client.data(for: request) }
        catch is CancellationError { throw CancellationError() }
        catch { throw WikiVibeKeysError.network }
        try Task.checkCancellation()
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if account && status == 401 { throw WikiVibeKeysError.unauthorized }
        if status == 401 || status == 403 { throw account ? WikiVibeKeysError.denied : WikiVibeKeysError.keyDenied }
        guard (200..<300).contains(status), data.count <= 2 * 1024 * 1024 else { throw WikiVibeKeysError.unreadable }
        return data
    }
}
