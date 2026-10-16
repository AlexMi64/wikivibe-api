import Foundation

struct WikiVibeAgentRequest: Encodable, CustomStringConvertible {
    struct Value: Encodable {
        struct Model: Encodable {
            let id: String
            let type: String?
            let protocols: [String]?
            let contextWindow: Int?
            init(id: String, type: String? = nil, protocols: [String]? = nil, contextWindow: Int? = nil) {
                self.id = id; self.type = type; self.protocols = protocols; self.contextWindow = contextWindow
            }
        }
        let apiKey: String
        let baseUrl: String
        let models: [Model]
        let protocols: [String]?
    }
    var operation: String
    let agentIds: [String]
    let value: Value?
    var fingerprint: String?
    var description: String { "WikiVibeAgentRequest(operation: \(operation), credentials: redacted)" }
}

struct WikiVibeAgentReport: Decodable, Identifiable {
    struct Change: Decodable, Identifiable {
        let agentId: String
        let path: String
        let secretOnDisk: Bool?
        var id: String { agentId + ":" + path }
        var displayPath: String {
            let home = FileManager.default.homeDirectoryForCurrentUser.path + "/"
            return path.hasPrefix(home) ? "~/" + path.dropFirst(home.count) : path
        }
    }
    struct Failure: Decodable, Identifiable {
        let agentId: String
        let error: String
        var id: String { agentId }
        var message: String { WikiVibeAgentService.error(error).localizedDescription }
    }
    let ok: Bool
    let error: String?
    let changes: [Change]?
    let failures: [Failure]?
    let fingerprint: String?
    var id: String { fingerprint ?? "result" }
}

/// A local adapter receives secrets over stdin, never argv, environment, a
/// temporary request file or the system log. Its environment contains no tokens.
struct WikiVibeAgentService {
    let home: URL
    let runner: URL?
    init(home: URL = FileManager.default.homeDirectoryForCurrentUser, runner: URL? = nil) {
        self.home = home
        self.runner = runner ?? Bundle.main.url(forResource: "runner", withExtension: "mjs", subdirectory: "AgentSetup")
    }
    static var nodeURL: URL? {
        let paths = ["/opt/homebrew/bin", "/usr/local/bin"]
            + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        return paths.filter { $0.hasPrefix("/") }.map { URL(fileURLWithPath: $0).appendingPathComponent("node") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
    static func error(_ code: String) -> WikiVibeKeysError {
        switch code {
        case "nodeMissing": return .nodeMissing
        case "conflict": return .conflict
        case "invalidConfiguration": return .invalidConfiguration
        case "unsafePath": return .unsafePath
        case "locked": return .locked
        default: return .setupFailed
        }
    }
    func run(_ request: WikiVibeAgentRequest) async throws -> WikiVibeAgentReport {
        guard let node = Self.nodeURL else { throw WikiVibeKeysError.nodeMissing }
        guard let runner, FileManager.default.fileExists(atPath: runner.path) else { throw WikiVibeKeysError.adapterMissing }
        let payload = try JSONEncoder().encode(request)
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = node
                process.arguments = [runner.path]
                process.currentDirectoryURL = runner.deletingLastPathComponent()
                process.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8"]
                let input = Pipe(), output = Pipe()
                process.standardInput = input
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice
                let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
                do {
                    try process.run()
                    DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: timeout)
                    try input.fileHandleForWriting.write(contentsOf: payload)
                    try input.fileHandleForWriting.close()
                    let data = output.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    timeout.cancel()
                    guard process.terminationStatus == 0, data.count <= 2 * 1024 * 1024,
                          let report = try? JSONDecoder().decode(WikiVibeAgentReport.self, from: data) else {
                        throw WikiVibeKeysError.setupFailed
                    }
                    guard report.ok else { throw Self.error(report.error ?? "setupFailed") }
                    continuation.resume(returning: report)
                } catch {
                    timeout.cancel()
                    if process.isRunning { process.terminate() }
                    try? input.fileHandleForWriting.close()
                    continuation.resume(throwing: (error as? WikiVibeKeysError) ?? WikiVibeKeysError.setupFailed)
                }
            }
        }
    }
}

@MainActor
final class WikiVibeKeysController: ObservableObject {
    static let contextWindowOptions: [Int?] = [nil, 128_000, 250_000, 500_000, 1_000_000, 1_050_000, 2_000_000]
    static func contextLabel(_ value: Int?) -> String {
        guard let value else { return L10n.t("No override") }
        if value % 1_000_000 == 0 { return "\(value / 1_000_000)M" }
        if value % 1_000 == 0 { return "\(value / 1_000)K" }
        return String(value)
    }
    @Published var contextWindows = [String: Int]() {
        didSet {
            if let ownerID, let selectedKeyID {
                defaults.set(contextWindows, forKey: contextStorageKey(ownerID: ownerID, keyID: selectedKeyID, gateway: gateway))
            }
            preview = nil; pending = nil; result = nil; error = nil
        }
    }
    @Published private(set) var keys = [WikiVibeAccountKey]()
    @Published private(set) var models = [WikiVibeModel]()
    @Published private(set) var isBusy = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var error: String?
    @Published private(set) var preview: WikiVibeAgentReport?
    @Published private(set) var result: WikiVibeAgentReport?
    @Published private(set) var isRestoring = false
    @Published var selectedKeyID: Int? {
        didSet {
            invalidatePreview()
            if let ownerID { defaults.set(selectedKeyID, forKey: "apiKeys.selectedKey.\(ownerID)") }
            contextWindows = loadContextWindows()
        }
    }
    @Published var gateway: WikiVibeGateway {
        didSet {
            defaults.set(gateway.rawValue, forKey: "apiKeys.gateway")
            invalidatePreview()
            contextWindows = loadContextWindows()
        }
    }
    @Published var agents: Set<WikiVibeAgent> {
        didSet { defaults.set(agents.map(\.rawValue).sorted(), forKey: "apiKeys.agents"); preview = nil; pending = nil; result = nil; error = nil }
    }
    private let api: WikiVibeKeysAPI
    private let service: WikiVibeAgentService
    private let defaults: UserDefaults
    private var ownerID: Int?
    private var generation = UUID()
    private var pending: WikiVibeAgentRequest?
    var selectedKey: WikiVibeAccountKey? { keys.first { $0.id == selectedKeyID } }
    var effectiveAgents: [WikiVibeAgent] {
        WikiVibeAgent.allCases.filter { agents.contains($0) && $0.supports(selectedKey?.protocols) }
    }
    var canPreview: Bool { selectedKey?.isUsable == true && !effectiveAgents.isEmpty && !isBusy }
    private func contextStorageKey(ownerID: Int, keyID: Int, gateway: WikiVibeGateway) -> String {
        "apiKeys.contextWindows.\(ownerID).\(keyID).\(gateway.rawValue)"
    }
    private func loadContextWindows() -> [String: Int] {
        guard let ownerID, let selectedKeyID,
              let saved = defaults.dictionary(forKey: contextStorageKey(ownerID: ownerID, keyID: selectedKeyID, gateway: gateway)) else { return [:] }
        return saved.reduce(into: [String: Int]()) { result, entry in
            if let value = entry.value as? Int, value > 0 { result[entry.key] = value }
        }
    }
    init(api: WikiVibeKeysAPI = WikiVibeKeysAPI(), service: WikiVibeAgentService = WikiVibeAgentService(), defaults: UserDefaults = .standard) {
        self.api = api; self.service = service; self.defaults = defaults
        gateway = defaults.string(forKey: "apiKeys.gateway").flatMap(WikiVibeGateway.init(rawValue:)) ?? .primary
        agents = Set((defaults.stringArray(forKey: "apiKeys.agents") ?? WikiVibeAgent.allCases.map(\.rawValue)).compactMap(WikiVibeAgent.init(rawValue:)))
    }
    func clear() {
        generation = UUID()
        ownerID = nil
        selectedKeyID = nil
        contextWindows = [:]
        keys = []; models = []; pending = nil; preview = nil; result = nil
        hasLoaded = false; isBusy = false; error = nil
    }
    private func invalidatePreview() {
        generation = UUID(); isBusy = false
        preview = nil; pending = nil; models = []; result = nil; error = nil
    }
    func cancelPreview() { preview = nil; pending = nil }
    func load(auth: WikiVibeAuthCoordinator) async {
        guard !isBusy else { return }
        guard let id = auth.account?.id else { clear(); return }
        let requestID = UUID(); generation = requestID
        ownerID = id; isBusy = true; error = nil
        defer { if generation == requestID { isBusy = false } }
        do {
            let fetched = try await auth.accountAPIKeys(using: api)
            try Task.checkCancellation()
            guard generation == requestID, auth.account?.id == id else { return }
            keys = fetched; hasLoaded = true
            let savedID = defaults.object(forKey: "apiKeys.selectedKey.\(id)") as? Int
            selectedKeyID = fetched.first(where: { $0.id == (selectedKeyID ?? savedID) && $0.isUsable })?.id
        } catch is CancellationError { }
        catch { if generation == requestID { keys = []; selectedKeyID = nil; self.error = safeMessage(error) } }
    }
    func loadModels(auth: WikiVibeAuthCoordinator) async {
        guard !isBusy, auth.account?.id == ownerID,
              let key = selectedKey, key.isUsable, let secret = key.key else { return }
        let requestID = generation
        isBusy = true; error = nil
        defer { if generation == requestID { isBusy = false } }
        do {
            let catalog = try await api.models(gateway: gateway, key: secret)
            try Task.checkCancellation()
            guard generation == requestID, auth.account?.id == ownerID else { return }
            models = catalog
        } catch is CancellationError { }
        catch { if generation == requestID { self.error = safeMessage(error) } }
    }
    func prepare(auth: WikiVibeAuthCoordinator, restore: Bool = false) async {
        guard !isBusy, auth.account?.id == ownerID else { return }
        let requestID = generation
        isBusy = true; error = nil; result = nil; isRestoring = restore
        defer { if generation == requestID { isBusy = false } }
        do {
            let value: WikiVibeAgentRequest.Value?
            let chosen: [WikiVibeAgent]
            if restore {
                value = nil; chosen = WikiVibeAgent.allCases.filter { agents.contains($0) }
            } else {
                guard let key = selectedKey, key.isUsable, let secret = key.key, !effectiveAgents.isEmpty else { throw WikiVibeKeysError.unusableKey }
                let catalog = models.isEmpty ? try await api.models(gateway: gateway, key: secret) : models
                try Task.checkCancellation()
                guard generation == requestID, auth.account?.id == ownerID else { return }
                models = catalog; chosen = effectiveAgents
                value = .init(apiKey: secret, baseUrl: gateway.rawValue, models: catalog.map { .init(id: $0.id, type: $0.type, protocols: $0.protocols, contextWindow: contextWindows[$0.id]) }, protocols: key.protocols)
            }
            guard !chosen.isEmpty else { throw WikiVibeKeysError.unusableKey }
            let request = WikiVibeAgentRequest(operation: restore ? "previewRestore" : "preview", agentIds: chosen.map(\.rawValue), value: value)
            let report = try await service.run(request)
            guard generation == requestID, auth.account?.id == ownerID else { return }
            pending = request; preview = report
        } catch is CancellationError { }
        catch { if generation == requestID { self.error = safeMessage(error) } }
    }
    /// Called only by the explicit confirmation button, never by a selection.
    func apply(auth: WikiVibeAuthCoordinator) async {
        guard !isBusy, auth.account?.id == ownerID, var request = pending,
              let stamp = preview?.fingerprint, !(preview?.changes?.isEmpty ?? true) else { return }
        request.operation = isRestoring ? "restore" : "apply"; request.fingerprint = stamp
        let requestID = generation
        pending = nil; preview = nil; isBusy = true; error = nil
        defer { if generation == requestID { isBusy = false } }
        do {
            let report = try await service.run(request)
            guard generation == requestID else { return }
            result = report
        } catch { if generation == requestID { self.error = safeMessage(error) } }
    }
    private func safeMessage(_ error: Error) -> String {
        (error as? WikiVibeKeysError)?.localizedDescription ?? WikiVibeKeysError.network.localizedDescription
    }
}
