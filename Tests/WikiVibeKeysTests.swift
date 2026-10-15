import XCTest
import CryptoKit
@testable import Codenotch

@MainActor
final class WikiVibeKeysTests: XCTestCase {
    private var client: URLSession!
    override func tearDown() {
        client?.invalidateAndCancel()
        KeysProtocol.handler = nil
        super.tearDown()
    }
    private func api(_ handler: @escaping (URLRequest) throws -> (Int, String)) -> WikiVibeKeysAPI {
        KeysProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [KeysProtocol.self]
        client = URLSession(configuration: configuration)
        return WikiVibeKeysAPI(client: client)
    }
    func testAllPagesAreReadWithoutDuplicateKeyIdentities() async throws {
        let service = api { request in
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertEqual(request.url?.path, "/api/v1/keys")
            let page = query.first { $0.name == "page" }?.value
            if page == "1" {
                return (200, #"{"code":0,"data":{"pages":2,"items":[{"id":1,"name":"first","key":"fixture-key-one","status":"active"}]}}"#)
            }
            XCTAssertEqual(page, "2")
            return (200, #"{"code":0,"data":{"pages":2,"items":[{"id":1,"name":"duplicate","key":"fixture-key-one","status":"active"},{"id":2,"name":"second","key":"fixture-key-two","status":"inactive"}]}}"#)
        }
        let keys = try await service.keys(accessToken: "fixture-session")
        XCTAssertEqual(keys.map(\.id), [1, 2])
        XCTAssertEqual(keys.first?.name, "first")
        XCTAssertEqual(keys.map(\.isUsable), [true, false])
    }
    func testCatalogDeduplicatesAndRefusesSecretEchoes() async throws {
        let service = api { request in
            XCTAssertEqual(request.url?.path, "/v1/models")
            return (200, #"{"data":[{"id":"z-model"},{"id":"a-model"},{"id":"z-model"}]}"#)
        }
        let models = try await service.models(gateway: .primary, key: "fixture-api-key")
        XCTAssertEqual(models, ["a-model", "z-model"])
        KeysProtocol.handler = { _ in (200, #"{"data":[{"id":"echo-fixture-api-key"}]}"#) }
        do {
            _ = try await service.models(gateway: .primary, key: "fixture-api-key")
            XCTFail("Credential echo was accepted as a model")
        } catch WikiVibeKeysError.unreadable { }
    }
    func testKeyRefusalIsNotAnExpiredAccountSession() async throws {
        let service = api { _ in (401, #"{"message":"fixture-api-key"}"#) }
        do {
            _ = try await service.models(gateway: .alternative, key: "fixture-api-key")
            XCTFail("Refused API key was accepted")
        } catch WikiVibeKeysError.keyDenied { }
        KeysProtocol.handler = { _ in (403, "access denied") }
        do {
            _ = try await service.keys(accessToken: "fixture-session")
            XCTFail("Forbidden panel response was accepted")
        } catch WikiVibeKeysError.denied { }
    }
    func testWalletAndKeyRequestsShareRotatingRefreshCredential() async throws {
        let started = expectation(description: "refresh started")
        let keyStarted = expectation(description: "key requested")
        let authAPI = KeysAuthFixture(refreshStarted: started)
        let store = KeysStore(authAPI.initial)
        let auth = WikiVibeAuthCoordinator(api: authAPI, store: store)
        await auth.restore(); auth.stopWalletPolling()
        await authAPI.expireAccess()
        let wallet = Task { await auth.loadWallet() }
        await fulfillment(of: [started], timeout: 2)
        let keysAPI = KeysFixture(started: keyStarted)
        let keys = Task { try await auth.accountAPIKeys(using: keysAPI) }
        await fulfillment(of: [keyStarted], timeout: 2)
        await authAPI.releaseRefresh()
        await wallet.value
        _ = try await keys.value
        let refreshCount = await authAPI.refreshCount
        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(store.value?.refreshToken, "rotated-refresh")
        XCTAssertNotNil(auth.wallet)
        XCTAssertNotNil(auth.account)
    }
    func testOldKeyResponseAfterSigningBackIntoSameAccountIsDiscarded() async throws {
        let requested = expectation(description: "key request suspended")
        let authAPI = KeysAuthFixture(refreshStarted: nil)
        let store = KeysStore(authAPI.initial)
        let auth = WikiVibeAuthCoordinator(api: authAPI, store: store)
        await auth.restore(); auth.stopWalletPolling()
        let keysAPI = KeysFixture(started: requested, suspend: true)
        let task = Task { try await auth.accountAPIKeys(using: keysAPI) }
        await fulfillment(of: [requested], timeout: 2)
        await auth.signOut()
        store.value = authAPI.initial
        await auth.restore(); auth.stopWalletPolling()
        await keysAPI.release()
        do { _ = try await task.value; XCTFail("Previous session's key data was returned") }
        catch is CancellationError { }
        XCTAssertEqual(auth.state, .signedIn(authAPI.initial.account))
    }
    func testAgentWritesRequirePreviewAndPreserveOriginalFiles() async throws {
        guard WikiVibeAgentService.nodeURL != nil else { throw XCTSkip("Node.js is not installed") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let original = "{\n  // retain this comment\n  \"model\": \"other/keep\",\n  \"provider\": {\"other\": {\"name\": \"Keep\"}}\n}\n"
        let config = root.appendingPathComponent(".config/opencode/opencode.jsonc")
        try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try Data(original.utf8).write(to: config)
        let service = WikiVibeAgentService(home: root)
        let value = WikiVibeAgentRequest.Value(apiKey: "fixture-safe-key", baseUrl: WikiVibeGateway.primary.rawValue,
                                              models: [.init(id: "gpt-fixture"), .init(id: "other-fixture")], protocols: nil)
        var request = WikiVibeAgentRequest(operation: "preview", agentIds: WikiVibeAgent.allCases.map(\.rawValue), value: value)
        let preview = try await service.run(request)
        XCTAssertEqual(try String(contentsOf: config, encoding: .utf8), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".codex/config.toml").path))
        XCTAssertTrue(preview.failures?.isEmpty == true)
        request.operation = "apply"; request.fingerprint = preview.fingerprint
        let applied = try await service.run(request)
        XCTAssertTrue(applied.failures?.isEmpty == true)
        let updated = try String(contentsOf: config, encoding: .utf8)
        XCTAssertTrue(updated.contains("// retain this comment"))
        XCTAssertTrue(updated.contains("other/keep"))
        let claude = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(".claude/settings.json"))) as! [String: Any]
        XCTAssertEqual((claude["env"] as? [String: String])?["ANTHROPIC_BASE_URL"], "https://api.wikivibe.dev")
        var restore = WikiVibeAgentRequest(operation: "previewRestore", agentIds: request.agentIds, value: nil)
        let restorePreview = try await service.run(restore)
        restore.operation = "restore"; restore.fingerprint = restorePreview.fingerprint
        let restored = try await service.run(restore)
        XCTAssertTrue(restored.failures?.isEmpty == true)
        XCTAssertEqual(try String(contentsOf: config, encoding: .utf8), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".claude/settings.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".codex/config.toml").path))
    }
    func testFilesChangedAfterPreviewAreNotWritten() async throws {
        guard WikiVibeAgentService.nodeURL != nil else { throw XCTSkip("Node.js is not installed") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let service = WikiVibeAgentService(home: root)
        var request = WikiVibeAgentRequest(operation: "preview", agentIds: ["opencode"],
            value: .init(apiKey: "fixture-safe-key", baseUrl: WikiVibeGateway.primary.rawValue, models: [.init(id: "fixture-model")], protocols: nil))
        let preview = try await service.run(request)
        let config = root.appendingPathComponent(".config/opencode/opencode.json")
        try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let userEdit = Data(#"{"model":"other/after-preview"}"#.utf8)
        try userEdit.write(to: config)
        request.operation = "apply"; request.fingerprint = preview.fingerprint
        do { _ = try await service.run(request); XCTFail("Stale preview was applied") }
        catch WikiVibeKeysError.conflict { }
        XCTAssertEqual(try Data(contentsOf: config), userEdit)
    }

    func testResponsesOnlyKeyRoutesNonGPTModelsAndProtectsSecretFiles() async throws {
        guard WikiVibeAgentService.nodeURL != nil else { throw XCTSkip("Node.js is not installed") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let service = WikiVibeAgentService(home: root)
        var request = WikiVibeAgentRequest(operation: "preview", agentIds: ["opencode"],
            value: .init(apiKey: "fixture-safe-key", baseUrl: WikiVibeGateway.primary.rawValue, models: [.init(id: "non-gpt-fixture")], protocols: ["openai_responses"]))
        let preview = try await service.run(request)
        request.operation = "apply"; request.fingerprint = preview.fingerprint
        _ = try await service.run(request)
        let config = root.appendingPathComponent(".config/opencode/opencode.json")
        let parsed = try JSONSerialization.jsonObject(with: Data(contentsOf: config)) as! [String: Any]
        let provider = (parsed["provider"] as! [String: Any])["wikivibe"] as! [String: Any]
        let model = (provider["models"] as! [String: Any])["non-gpt-fixture"] as! [String: Any]
        XCTAssertEqual((model["provider"] as? [String: String])?["npm"], "@ai-sdk/openai")
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: config.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let backup = config.deletingLastPathComponent().appendingPathComponent(".wikivibe-gateway-backups")
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: backup.path)[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }
    func testImageModelsUseOhMyPiResponsesRoleOnly() async throws {
        guard WikiVibeAgentService.nodeURL != nil else { throw XCTSkip("Node.js is not installed") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let service = WikiVibeAgentService(home: root)
        let value = WikiVibeAgentRequest.Value(apiKey: "fixture-safe-key", baseUrl: WikiVibeGateway.primary.rawValue,
                                              models: [.init(id: "gpt-image-2"), .init(id: "gpt-6.1-sol")], protocols: nil)
        var request = WikiVibeAgentRequest(operation: "preview", agentIds: WikiVibeAgent.allCases.map(\.rawValue), value: value)
        let preview = try await service.run(request)
        XCTAssertTrue(preview.failures?.isEmpty == true)
        request.operation = "apply"; request.fingerprint = preview.fingerprint
        let applied = try await service.run(request)
        XCTAssertTrue(applied.failures?.isEmpty == true)

        let ompConfig = try String(contentsOf: root.appendingPathComponent(".omp/agent/config.yml"), encoding: .utf8)
        XCTAssertTrue(ompConfig.contains("wikivibe/gpt-image-2"))
        let ompModels = try String(contentsOf: root.appendingPathComponent(".omp/agent/models.yml"), encoding: .utf8)
        XCTAssertTrue(ompModels.contains("gpt-image-2"))
        XCTAssertTrue(ompModels.contains("openai-responses"))
        XCTAssertFalse(try String(contentsOf: root.appendingPathComponent(".config/opencode/opencode.json"), encoding: .utf8).contains("gpt-image-2"))
        XCTAssertFalse(try String(contentsOf: root.appendingPathComponent(".claude/settings.json"), encoding: .utf8).contains("gpt-image-2"))
        XCTAssertFalse(try String(contentsOf: root.appendingPathComponent(".codex/wikivibe-models.json"), encoding: .utf8).contains("gpt-image-2"))
        var restore = WikiVibeAgentRequest(operation: "previewRestore", agentIds: request.agentIds, value: nil)
        let restorePreview = try await service.run(restore)
        restore.operation = "restore"; restore.fingerprint = restorePreview.fingerprint
        let restored = try await service.run(restore)
        XCTAssertTrue(restored.failures?.isEmpty == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".omp/agent/config.yml").path))
    }

    func testOhMyPiExistingImageRoleIsPreserved() async throws {
        guard WikiVibeAgentService.nodeURL != nil else { throw XCTSkip("Node.js is not installed") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let directory = root.appendingPathComponent(".omp/agent")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let config = directory.appendingPathComponent("config.yml")
        let original = "modelRoles:\n  image: user/custom-image\ngenerate_image:\n  enabled: false\n"
        try Data(original.utf8).write(to: config)
        let service = WikiVibeAgentService(home: root)
        let value = WikiVibeAgentRequest.Value(apiKey: "fixture-safe-key", baseUrl: WikiVibeGateway.primary.rawValue,
                                              models: [.init(id: "gpt-image-2"), .init(id: "gpt-6.1-sol")], protocols: nil)
        var request = WikiVibeAgentRequest(operation: "preview", agentIds: ["omp"], value: value)
        let preview = try await service.run(request)
        XCTAssertTrue(preview.failures?.isEmpty == true)
        request.operation = "apply"; request.fingerprint = preview.fingerprint
        _ = try await service.run(request)
        XCTAssertEqual(try String(contentsOf: config, encoding: .utf8), original)
    }

    func testOhMyPiImageRolePreservesUserRemovalOnReapply() async throws {
        guard WikiVibeAgentService.nodeURL != nil else { throw XCTSkip("Node.js is not installed") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let service = WikiVibeAgentService(home: root)
        let value = WikiVibeAgentRequest.Value(apiKey: "fixture-safe-key", baseUrl: WikiVibeGateway.primary.rawValue,
                                              models: [.init(id: "gpt-image-2"), .init(id: "gpt-6.1-sol")], protocols: ["openai_responses"])
        var request = WikiVibeAgentRequest(operation: "preview", agentIds: ["omp"], value: value)
        var preview = try await service.run(request)
        request.operation = "apply"; request.fingerprint = preview.fingerprint
        _ = try await service.run(request)
        let config = root.appendingPathComponent(".omp/agent/config.yml")
        try Data("modelRoles:\n  text: wikivibe/gpt-6.1-sol\n".utf8).write(to: config)
        request.operation = "preview"; request.fingerprint = nil
        preview = try await service.run(request)
        XCTAssertTrue(preview.failures?.isEmpty == true)
        request.operation = "apply"; request.fingerprint = preview.fingerprint
        _ = try await service.run(request)
        XCTAssertEqual(try String(contentsOf: config, encoding: .utf8), "modelRoles:\n  text: wikivibe/gpt-6.1-sol\n")
    }
    func testOhMyPiRejectsImageRoleWithoutResponsesOrCarrier() async throws {
        guard WikiVibeAgentService.nodeURL != nil else { throw XCTSkip("Node.js is not installed") }
        for (ids, protocols) in [
            (["gpt-image-2", "gpt-6.1-sol"], ["openai_chat_completions"]),
            (["gpt-image-2", "other-chat"], ["openai_responses"])
        ] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: root) }
            let service = WikiVibeAgentService(home: root)
            let value = WikiVibeAgentRequest.Value(apiKey: "fixture-safe-key", baseUrl: WikiVibeGateway.primary.rawValue,
                                                  models: ids.map { .init(id: $0) }, protocols: protocols)
            var request = WikiVibeAgentRequest(operation: "preview", agentIds: ["omp"], value: value)
            let preview = try await service.run(request)
            XCTAssertTrue(preview.failures?.isEmpty == true)
            request.operation = "apply"; request.fingerprint = preview.fingerprint
            let applied = try await service.run(request)
            XCTAssertTrue(applied.failures?.isEmpty == true)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".omp/agent/config.yml").path))
            XCTAssertFalse(try String(contentsOf: root.appendingPathComponent(".omp/agent/models.yml"), encoding: .utf8).contains("gpt-image-2"))
        }
    }

    func testCodexActivationRestoresOriginalDefaultConfiguration() async throws {
        guard WikiVibeAgentService.nodeURL != nil else { throw XCTSkip("Node.js is not installed") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent(".codex/config.toml")
        try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let original = Data("model = 'old-model'\r\nmodel_provider = 'other'\r\nprofile = 'work'\r\n[profiles.work]\r\nmodel = 'gpt-fixture'\r\n[model_providers.other]\r\nname = 'Keep'\r\n".utf8)
        try original.write(to: config)
        let service = WikiVibeAgentService(home: root)
        var request = WikiVibeAgentRequest(operation: "preview", agentIds: ["codex"],
            value: .init(apiKey: "fixture-safe-key", baseUrl: WikiVibeGateway.primary.rawValue, models: [.init(id: "other-fixture"), .init(id: "gpt-fixture")], protocols: ["openai_responses"]))
        let preview = try await service.run(request)
        XCTAssertEqual(try Data(contentsOf: config), original)
        XCTAssertTrue(preview.failures?.isEmpty == true)
        request.operation = "apply"; request.fingerprint = preview.fingerprint
        let applied = try await service.run(request)
        XCTAssertTrue(applied.failures?.isEmpty == true)
        let catalogURL = root.appendingPathComponent(".codex/wikivibe-models.json")
        let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as! [String: Any]
        XCTAssertEqual((catalog["models"] as? [[String: Any]])?.compactMap { $0["slug"] as? String }, ["other-fixture", "gpt-fixture"])
        var restore = WikiVibeAgentRequest(operation: "previewRestore", agentIds: ["codex"], value: nil)
        let restorePreview = try await service.run(restore)
        restore.operation = "restore"; restore.fingerprint = restorePreview.fingerprint
        let restored = try await service.run(restore)
        XCTAssertTrue(restored.failures?.isEmpty == true)
        XCTAssertEqual(try Data(contentsOf: config), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: catalogURL.path))
    }

    func testCodexCutoverRemovesOwnedProfileButRefusesLaterEdits() async throws {
        guard WikiVibeAgentService.nodeURL != nil else { throw XCTSkip("Node.js is not installed") }
        for edited in [false, true] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: root) }
            let directory = root.appendingPathComponent(".codex")
            let backupDirectory = directory.appendingPathComponent(".wikivibe-gateway-backups")
            try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let profile = directory.appendingPathComponent("wikivibe.config.toml")
            let previous = Data("model_provider = \"wikivibe\"\n".utf8)
            let current = edited ? previous + Data("# user edit\n".utf8) : previous
            try current.write(to: profile)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: profile.path)
            let record: [String: Any] = ["version": 1, "agentId": "codex", "rel": ".codex/wikivibe.config.toml", "original": NSNull(), "state": "active",
                                       "appliedHash": SHA256.hash(data: previous).map { String(format: "%02x", $0) }.joined()]
            let backup = backupDirectory.appendingPathComponent("wikivibe.config.toml.json")
            try JSONSerialization.data(withJSONObject: record).write(to: backup)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
            let service = WikiVibeAgentService(home: root)
            var request = WikiVibeAgentRequest(operation: "preview", agentIds: ["codex"],
                value: .init(apiKey: "fixture-safe-key", baseUrl: WikiVibeGateway.primary.rawValue, models: [.init(id: "gpt-fixture")], protocols: ["openai_responses"]))
            let preview = try await service.run(request)
            if edited {
                XCTAssertEqual(preview.failures?.map(\.agentId), ["codex"])
                XCTAssertEqual(try Data(contentsOf: profile), current)
                XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("config.toml").path))
            } else {
                XCTAssertTrue(preview.failures?.isEmpty == true)
                request.operation = "apply"; request.fingerprint = preview.fingerprint
                let applied = try await service.run(request)
                XCTAssertTrue(applied.failures?.isEmpty == true)
                XCTAssertFalse(FileManager.default.fileExists(atPath: profile.path))
                XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path))
            }
        }
    }
    func testConfirmationAcceptsReorderedJSONFields() throws {
        guard let node = WikiVibeAgentService.nodeURL else { throw XCTSkip("Node.js is not installed") }
        let runner = try XCTUnwrap(Bundle.main.url(forResource: "runner", withExtension: "mjs", subdirectory: "AgentSetup"))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        func invoke(_ json: String) throws -> WikiVibeAgentReport {
            let process = Process(), input = Pipe(), output = Pipe()
            process.executableURL = node
            process.arguments = [runner.path]
            process.environment = ["HOME": root.path, "PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8"]
            process.standardInput = input; process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            try process.run()
            try input.fileHandleForWriting.write(contentsOf: Data(json.utf8))
            try input.fileHandleForWriting.close()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return try JSONDecoder().decode(WikiVibeAgentReport.self, from: data)
        }
        let preview = try invoke(#"{"operation":"preview","agentIds":["opencode"],"value":{"baseUrl":"https://api.wikivibe.dev/v1","apiKey":"fixture-safe-key","models":[{"id":"fixture-model"}]}}"#)
        let fingerprint = try XCTUnwrap(preview.fingerprint)
        let applied = try invoke(#"{"operation":"apply","fingerprint":"\#(fingerprint)","agentIds":["opencode"],"value":{"models":[{"id":"fixture-model"}],"apiKey":"fixture-safe-key","baseUrl":"https://api.wikivibe.dev/v1"}}"#)
        XCTAssertTrue(applied.ok)
        let config = root.appendingPathComponent(".config/opencode/opencode.json")
        let parsed = try JSONSerialization.jsonObject(with: Data(contentsOf: config)) as! [String: Any]
        let provider = (parsed["provider"] as! [String: Any])["wikivibe"] as! [String: Any]
        XCTAssertEqual((provider["options"] as? [String: String])?["baseURL"], WikiVibeGateway.primary.rawValue)
    }
}

private final class KeysProtocol: URLProtocol, @unchecked Sendable {
    static var handler: ((URLRequest) throws -> (Int, String))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, body) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

private final class KeysStore: WikiVibeSessionStoreInterface {
    var value: WikiVibeSession?
    init(_ value: WikiVibeSession) { self.value = value }
    func load() -> WikiVibeSession? { value }
    func save(_ session: WikiVibeSession) -> Bool { value = session; return true }
    func clear() -> Bool { value = nil; return true }
}

private actor KeysAuthFixture: WikiVibeAuthAPIInterface {
    nonisolated let initial = WikiVibeSession(accessToken: "initial-access", refreshToken: "initial-refresh", expiresIn: 3600,
                                              account: WikiVibeAccount(id: 7, username: "fixture", email: ""))
    let refreshStarted: XCTestExpectation?
    var refreshCount = 0
    private var expired = false
    private var continuation: CheckedContinuation<Void, Never>?
    init(refreshStarted: XCTestExpectation?) { self.refreshStarted = refreshStarted }
    func expireAccess() { expired = true }
    func releaseRefresh() { continuation?.resume(); continuation = nil }
    nonisolated func authorizationURL(pkce: WikiVibePKCE, redirectURI: String) throws -> URL { URL(string: "https://auth.wikivibe.dev")! }
    func exchange(code: String, verifier: String, redirectURI: String) async throws -> WikiVibeSession { throw WikiVibeAuthError.sessionExpired }
    func refresh(using session: WikiVibeSession) async throws -> WikiVibeSession {
        refreshCount += 1
        if refreshCount == 1, refreshStarted != nil {
            await withCheckedContinuation { continuation = $0; refreshStarted?.fulfill() }
        }
        return WikiVibeSession(accessToken: "rotated-access", refreshToken: "rotated-refresh", expiresIn: 3600, account: initial.account)
    }
    func account(for session: WikiVibeSession) async throws -> WikiVibeAccount { initial.account }
    func wallet(for session: WikiVibeSession) async throws -> WikiVibeWallet {
        if expired && session.accessToken == initial.accessToken { throw WikiVibeAuthError.sessionExpired }
        return WikiVibeWallet(regular: 1, bonus: nil, frozen: nil, currencyName: "USD", currencySymbol: "$")
    }
    func revoke(refreshToken: String) async {}
}

private actor KeysFixture: WikiVibeKeysAPIInterface {
    let started: XCTestExpectation
    let suspend: Bool
    private var first = true
    private var continuation: CheckedContinuation<Void, Never>?
    init(started: XCTestExpectation, suspend: Bool = false) { self.started = started; self.suspend = suspend }
    func release() { continuation?.resume(); continuation = nil }
    func keys(accessToken: String) async throws -> [WikiVibeAccountKey] {
        if first {
            first = false
            if suspend { await withCheckedContinuation { continuation = $0; started.fulfill() } }
            else { started.fulfill() }
        }
        if !suspend && accessToken == "initial-access" { throw WikiVibeKeysError.unauthorized }
        return []
    }
}
