import CryptoKit
import XCTest
@testable import Codenotch

final class PhoneLinkTests: XCTestCase {
    private struct Vector: Decodable {
        struct Sample: Decodable {
            let ts: String
            let nonce: String
            let method: String
            let path: String
            let uri: String
            let plaintext: String
            let gcmNonce: String
            let aad: String
            let envelopeBase64: String
            let signature: String
        }

        let code: String
        let deviceId: String
        let S: String
        let K_sig: String
        let K_enc: String
        let K_pair_sig: String
        let K_pair_enc: String
        let sample: Sample
    }

    private struct PairResponse: Decodable {
        let paired: Bool
        let server: String
        let version: String
        let api: Int
        let deviceId: String
    }

    func testV3Vectors() throws {
        let vectorURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("phone-link-v3-vectors.json")
        let vector = try JSONDecoder().decode(Vector.self, from: Data(contentsOf: vectorURL))

        let secret = try PhoneLinkCrypto.deviceSecret(code: vector.code, deviceId: vector.deviceId)
        let deviceKeys = PhoneLinkCrypto.deviceKeys(secret: secret)
        let pairingKeys = try PhoneLinkCrypto.pairingKeys(code: vector.code)

        XCTAssertEqual(secret.hexString, vector.S)
        XCTAssertEqual(PhoneLinkCrypto.keyData(deviceKeys.signature).hexString, vector.K_sig)
        XCTAssertEqual(PhoneLinkCrypto.keyData(deviceKeys.encryption).hexString, vector.K_enc)
        XCTAssertEqual(PhoneLinkCrypto.keyData(pairingKeys.signature).hexString, vector.K_pair_sig)
        XCTAssertEqual(PhoneLinkCrypto.keyData(pairingKeys.encryption).hexString, vector.K_pair_enc)

        let aad = PhoneLinkCrypto.requestAAD(
            ts: vector.sample.ts,
            nonce: vector.sample.nonce,
            method: vector.sample.method,
            path: vector.sample.path,
            deviceId: vector.deviceId
        )
        XCTAssertEqual(String(data: aad, encoding: .utf8), vector.sample.aad)
        let envelope = try PhoneLinkCrypto.seal(
            Data(vector.sample.plaintext.utf8),
            key: deviceKeys.encryption,
            aad: aad,
            nonce: try XCTUnwrap(Data(hexString: vector.sample.gcmNonce))
        )
        XCTAssertEqual(String(data: envelope, encoding: .utf8), vector.sample.envelopeBase64)
        XCTAssertEqual(
            PhoneLinkCrypto.signatureHex(
                key: deviceKeys.signature,
                ts: vector.sample.ts,
                nonce: vector.sample.nonce,
                method: vector.sample.method,
                uri: vector.sample.uri,
                bodyAsSent: envelope
            ),
            vector.sample.signature
        )
    }

    func testResponseIsBoundToOriginatingRequest() throws {
        let secret = try PhoneLinkCrypto.deviceSecret(
            code: "00112233445566778899aabbccddeeff",
            deviceId: "01234567-89ab-cdef-0123-456789abcdef"
        )
        let key = PhoneLinkCrypto.deviceKeys(secret: secret).encryption
        let responseA = PhoneLinkCrypto.responseAAD(
            ts: "1757000000",
            nonce: "000102030405060708090a0b0c0d0e0f",
            method: "GET",
            path: "/api/v3/snapshot",
            deviceId: "01234567-89ab-cdef-0123-456789abcdef",
            status: 200
        )
        let responseB = PhoneLinkCrypto.responseAAD(
            ts: "1757000001",
            nonce: "101112131415161718191a1b1c1d1e1f",
            method: "GET",
            path: "/api/v3/snapshot",
            deviceId: "01234567-89ab-cdef-0123-456789abcdef",
            status: 200
        )
        let envelope = try PhoneLinkCrypto.seal(Data("response A".utf8), key: key, aad: responseA)

        XCTAssertThrowsError(try PhoneLinkCrypto.open(envelope, key: key, aad: responseB))
        XCTAssertEqual(try PhoneLinkCrypto.open(envelope, key: key, aad: responseA), Data("response A".utf8))
    }

    @MainActor
    func testPairingStartsClosedWithoutCode() {
        let pairing = PhoneLinkPairing()
        XCTAssertFalse(pairing.isOpen)
        XCTAssertNil(pairing.currentCode)
    }

    func testReplayStoreUsesProtocolScopes() async {
        let store = SecurityStore()
        let nonce = "00112233445566778899aabbccddeeff"
        let deviceAFirst = await store.checkAndStoreNonce(key: "device:A", nonce: nonce)
        let deviceAReplay = await store.checkAndStoreNonce(key: "device:A", nonce: nonce)
        let deviceBFirst = await store.checkAndStoreNonce(key: "device:B", nonce: nonce)
        let ipAFirst = await store.checkAndStoreNonce(key: "pair:192.168.1.2", nonce: nonce)
        let ipAReplay = await store.checkAndStoreNonce(key: "pair:192.168.1.2", nonce: nonce)
        let ipBFirst = await store.checkAndStoreNonce(key: "pair:192.168.1.3", nonce: nonce)
        XCTAssertTrue(deviceAFirst)
        XCTAssertFalse(deviceAReplay)
        XCTAssertTrue(deviceBFirst)
        XCTAssertTrue(ipAFirst)
        XCTAssertFalse(ipAReplay)
        XCTAssertTrue(ipBFirst)
    }

    func testRegistryPersistsMetadataButNotSecretAndRemoveClearsSecretStore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let secrets = InMemoryPhoneLinkSecretStore()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let registry = PhoneLinkRegistry(directory: directory, secretStore: secrets)
        let device = PairedDevice(
            deviceId: "A",
            name: "Phone",
            platform: "ios",
            pairedAt: Date(),
            lastSeenAt: Date(),
            lastSeenIP: "127.0.0.1"
        )
        let secret = Data(repeating: 0xab, count: 32)
        XCTAssertTrue(registry.addOrUpdate(device: device, secret: secret))
        waitForRegistryWrites()

        let file = try Data(contentsOf: directory.appendingPathComponent("devices.json"))
        XCTAssertFalse(String(decoding: file, as: UTF8.self).contains("secret"))
        XCTAssertEqual(secrets.read(deviceId: "A"), secret)

        let reloaded = PhoneLinkRegistry(directory: directory, secretStore: secrets)
        XCTAssertEqual(reloaded.getDevice(id: "A")?.name, "Phone")
        XCTAssertEqual(reloaded.secret(deviceId: "A"), secret)

        reloaded.remove(deviceId: "A")
        waitForRegistryWrites()
        XCTAssertNil(secrets.read(deviceId: "A"))
        XCTAssertNil(reloaded.secret(deviceId: "A"))
        XCTAssertNil(reloaded.getDevice(id: "A"))
    }

    func testV2RecordsAreDiscardedAndFileIsRewritten() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacy = """
        [{"deviceId":"old","name":"Old Phone","platform":"ios","pairedAt":0,"lastSeenAt":0,"lastSeenIP":"192.168.1.2","secret":"v2-secret"}]
        """
        try Data(legacy.utf8).write(to: directory.appendingPathComponent("devices.json"))
        let secrets = InMemoryPhoneLinkSecretStore()

        let registry = PhoneLinkRegistry(directory: directory, secretStore: secrets)

        XCTAssertTrue(registry.discardedLegacyDevices)
        XCTAssertNil(registry.getDevice(id: "old"))
        XCTAssertNil(secrets.read(deviceId: "old"))
        let rewritten = try Data(contentsOf: directory.appendingPathComponent("devices.json"))
        XCTAssertEqual(String(decoding: rewritten, as: UTF8.self), "[]")
    }

    @MainActor
    func testPairingEndpointIsClosedUntilWindowOpens() async throws {
        let context = try await makeServer()
        defer { context.cleanup() }

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(context.port)/api/v3/pair")!)
        request.httpMethod = "POST"
        let (data, response) = try await URLSession.shared.data(for: request)

        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 403)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "{\"error\":\"pairing-closed\"}")
        await context.server.stop()
    }

    @MainActor
    func testEnvelopeBodyCapIsAppliedBeforeDecoding() async throws {
        let context = try await makeServer()
        defer { context.cleanup() }
        context.pairing.openWindow()

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(context.port)/api/v3/pair")!)
        request.httpMethod = "POST"
        request.httpBody = Data(repeating: 0x41, count: 64 * 1024 + 1)
        let (data, response) = try await URLSession.shared.data(for: request)

        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 413)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "{\"error\":\"payload-too-large\"}")
        await context.server.stop()
    }

    @MainActor
    func testEncryptedPairingAndSnapshotIntegration() async throws {
        let context = try await makeServer(snapshot: Data("{\"snapshot\":true}".utf8))
        defer { context.cleanup() }
        context.pairing.openWindow()
        let code = try XCTUnwrap(context.pairing.currentCode)
        let deviceId = "9b38c882-35da-4dc1-8708-e676e6207333"
        let pairKeys = try PhoneLinkCrypto.pairingKeys(code: code)
        let pairTS = String(Int(Date().timeIntervalSince1970))
        let pairNonce = "00112233445566778899aabbccddeeff"
        let pairPlaintext = Data("{\"deviceId\":\"\(deviceId)\",\"name\":\"Test Phone\",\"platform\":\"ios\"}".utf8)
        let pairAAD = PhoneLinkCrypto.pairingRequestAAD(ts: pairTS, nonce: pairNonce, deviceId: deviceId)
        let pairEnvelope = try PhoneLinkCrypto.seal(pairPlaintext, key: pairKeys.encryption, aad: pairAAD)

        var pairRequest = URLRequest(url: URL(string: "http://127.0.0.1:\(context.port)/api/v3/pair")!)
        pairRequest.httpMethod = "POST"
        pairRequest.httpBody = pairEnvelope
        pairRequest.setValue("application/codenotch-v3", forHTTPHeaderField: "content-type")
        pairRequest.setValue(pairTS, forHTTPHeaderField: "x-cn-timestamp")
        pairRequest.setValue(pairNonce, forHTTPHeaderField: "x-cn-nonce")
        pairRequest.setValue(deviceId, forHTTPHeaderField: "x-cn-device")
        pairRequest.setValue(
            PhoneLinkCrypto.signatureHex(
                key: pairKeys.signature,
                ts: pairTS,
                nonce: pairNonce,
                method: "POST",
                uri: "/api/v3/pair",
                bodyAsSent: pairEnvelope
            ),
            forHTTPHeaderField: "x-cn-signature"
        )
        let (pairData, pairURLResponse) = try await URLSession.shared.data(for: pairRequest)
        let pairHTTPResponse = try XCTUnwrap(pairURLResponse as? HTTPURLResponse)
        XCTAssertEqual(pairHTTPResponse.statusCode, 200)
        XCTAssertEqual(pairHTTPResponse.value(forHTTPHeaderField: "content-type"), "application/codenotch-v3")
        XCTAssertNil(pairHTTPResponse.value(forHTTPHeaderField: "x-cn-signature"))
        let pairResponsePlaintext = try PhoneLinkCrypto.open(
            pairData,
            key: pairKeys.encryption,
            aad: PhoneLinkCrypto.pairingResponseAAD(ts: pairTS, nonce: pairNonce, deviceId: deviceId, status: 200)
        )
        let pairResponse = try JSONDecoder().decode(PairResponse.self, from: pairResponsePlaintext)
        XCTAssertTrue(pairResponse.paired)
        XCTAssertFalse(pairResponse.server.isEmpty)
        XCTAssertFalse(pairResponse.version.isEmpty)
        XCTAssertEqual(pairResponse.api, 3)
        XCTAssertEqual(pairResponse.deviceId, deviceId)
        XCTAssertFalse(context.pairing.isOpen)

        let secret = try PhoneLinkCrypto.deviceSecret(code: code, deviceId: deviceId)
        XCTAssertEqual(context.secrets.read(deviceId: deviceId), secret)
        let deviceKeys = PhoneLinkCrypto.deviceKeys(secret: secret)
        let snapshotTS = String(Int(Date().timeIntervalSince1970))
        let snapshotNonce = "102132435465768798a9bacbdcedfe0f"
        let snapshotPath = "/api/v3/snapshot"
        var snapshotRequest = URLRequest(url: URL(string: "http://127.0.0.1:\(context.port)\(snapshotPath)")!)
        snapshotRequest.httpMethod = "GET"
        snapshotRequest.setValue(snapshotTS, forHTTPHeaderField: "x-cn-timestamp")
        snapshotRequest.setValue(snapshotNonce, forHTTPHeaderField: "x-cn-nonce")
        snapshotRequest.setValue(deviceId, forHTTPHeaderField: "x-cn-device")
        snapshotRequest.setValue(
            PhoneLinkCrypto.signatureHex(
                key: deviceKeys.signature,
                ts: snapshotTS,
                nonce: snapshotNonce,
                method: "GET",
                uri: snapshotPath,
                bodyAsSent: Data()
            ),
            forHTTPHeaderField: "x-cn-signature"
        )
        XCTAssertNil(snapshotRequest.httpBody)
        XCTAssertNil(snapshotRequest.value(forHTTPHeaderField: "content-type"))
        let (snapshotData, snapshotURLResponse) = try await URLSession.shared.data(for: snapshotRequest)
        let snapshotHTTPResponse = try XCTUnwrap(snapshotURLResponse as? HTTPURLResponse)
        XCTAssertEqual(snapshotHTTPResponse.statusCode, 200)
        XCTAssertEqual(snapshotHTTPResponse.value(forHTTPHeaderField: "content-type"), "application/codenotch-v3")
        XCTAssertNil(snapshotHTTPResponse.value(forHTTPHeaderField: "x-cn-signature"))
        let snapshotPlaintext = try PhoneLinkCrypto.open(
            snapshotData,
            key: deviceKeys.encryption,
            aad: PhoneLinkCrypto.responseAAD(
                ts: snapshotTS,
                nonce: snapshotNonce,
                method: "GET",
                path: snapshotPath,
                deviceId: deviceId,
                status: 200
            )
        )
        XCTAssertEqual(snapshotPlaintext, Data("{\"snapshot\":true}".utf8))
        XCTAssertNotEqual(snapshotData, snapshotPlaintext)
        XCTAssertThrowsError(try PhoneLinkCrypto.open(
            snapshotData,
            key: deviceKeys.encryption,
            aad: PhoneLinkCrypto.responseAAD(
                ts: snapshotTS,
                nonce: "ffeeddccbbaa99887766554433221100",
                method: "GET",
                path: snapshotPath,
                deviceId: deviceId,
                status: 200
            )
        ))

        let refreshTS = String(Int(Date().timeIntervalSince1970))
        let refreshNonce = "2031425364758697a8b9cadbecfd0e1f"
        let refreshPath = "/api/v3/refresh"
        var refreshRequest = URLRequest(url: URL(string: "http://127.0.0.1:\(context.port)\(refreshPath)")!)
        refreshRequest.httpMethod = "POST"
        refreshRequest.setValue(refreshTS, forHTTPHeaderField: "x-cn-timestamp")
        refreshRequest.setValue(refreshNonce, forHTTPHeaderField: "x-cn-nonce")
        refreshRequest.setValue(deviceId, forHTTPHeaderField: "x-cn-device")
        refreshRequest.setValue(
            PhoneLinkCrypto.signatureHex(
                key: deviceKeys.signature,
                ts: refreshTS,
                nonce: refreshNonce,
                method: "POST",
                uri: refreshPath,
                bodyAsSent: Data()
            ),
            forHTTPHeaderField: "x-cn-signature"
        )
        XCTAssertNil(refreshRequest.httpBody)
        XCTAssertNil(refreshRequest.value(forHTTPHeaderField: "content-type"))
        let (refreshData, refreshURLResponse) = try await URLSession.shared.data(for: refreshRequest)
        let refreshHTTPResponse = try XCTUnwrap(refreshURLResponse as? HTTPURLResponse)
        XCTAssertEqual(refreshHTTPResponse.statusCode, 200)
        XCTAssertEqual(refreshHTTPResponse.value(forHTTPHeaderField: "content-type"), "application/codenotch-v3")
        XCTAssertNil(refreshHTTPResponse.value(forHTTPHeaderField: "x-cn-signature"))
        let refreshPlaintext = try PhoneLinkCrypto.open(
            refreshData,
            key: deviceKeys.encryption,
            aad: PhoneLinkCrypto.responseAAD(
                ts: refreshTS,
                nonce: refreshNonce,
                method: "POST",
                path: refreshPath,
                deviceId: deviceId,
                status: 200
            )
        )
        XCTAssertEqual(refreshPlaintext, Data("{\"snapshot\":true}".utf8))
        XCTAssertNotEqual(refreshData, refreshPlaintext)
        XCTAssertThrowsError(try PhoneLinkCrypto.open(
            refreshData,
            key: deviceKeys.encryption,
            aad: PhoneLinkCrypto.responseAAD(
                ts: String(Int(refreshTS)! + 1),
                nonce: refreshNonce,
                method: "POST",
                path: refreshPath,
                deviceId: deviceId,
                status: 200
            )
        ))

        let healthURL = URL(string: "http://127.0.0.1:\(context.port)/health")!
        let (healthData, healthResponse) = try await URLSession.shared.data(from: healthURL)
        XCTAssertEqual((healthResponse as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertTrue(String(decoding: healthData, as: UTF8.self).contains("\"api\":3"))
        await context.server.stop()
    }

    @MainActor
    func testBodilessSignedSnapshotReturnsEncrypted200() async throws {
        let snapshot = Data("{\"regression\":true}".utf8)
        let context = try await makeServer(snapshot: snapshot)
        defer { context.cleanup() }
        let deviceId = "5f798d46-049b-489b-85ad-9e3de53406d5"
        let secret = Data(repeating: 0xab, count: 32)
        let device = PairedDevice(
            deviceId: deviceId,
            name: "Regression Phone",
            platform: "ios",
            pairedAt: Date(),
            lastSeenAt: Date(),
            lastSeenIP: "127.0.0.1"
        )
        XCTAssertTrue(context.registry.addOrUpdate(device: device, secret: secret))

        let keys = PhoneLinkCrypto.deviceKeys(secret: secret)
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let nonce = "30415263748596a7b8c9daebfc0d1e2f"
        let path = "/api/v3/snapshot"
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(context.port)\(path)")!)
        request.httpMethod = "GET"
        request.setValue(timestamp, forHTTPHeaderField: "x-cn-timestamp")
        request.setValue(nonce, forHTTPHeaderField: "x-cn-nonce")
        request.setValue(deviceId, forHTTPHeaderField: "x-cn-device")
        request.setValue(
            PhoneLinkCrypto.signatureHex(
                key: keys.signature,
                ts: timestamp,
                nonce: nonce,
                method: "GET",
                uri: path,
                bodyAsSent: Data()
            ),
            forHTTPHeaderField: "x-cn-signature"
        )

        let (responseBody, urlResponse) = try await URLSession.shared.data(for: request)
        let response = try XCTUnwrap(urlResponse as? HTTPURLResponse)
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.value(forHTTPHeaderField: "content-type"), "application/codenotch-v3")
        XCTAssertEqual(
            try PhoneLinkCrypto.open(
                responseBody,
                key: keys.encryption,
                aad: PhoneLinkCrypto.responseAAD(
                    ts: timestamp,
                    nonce: nonce,
                    method: "GET",
                    path: path,
                    deviceId: deviceId,
                    status: 200
                )
            ),
            snapshot
        )
        await context.server.stop()
    }

    @MainActor
    func testServerFailsClosedWithoutPrivateNetwork() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = PhoneLinkRegistry(directory: directory, secretStore: InMemoryPhoneLinkSecretStore())
        let pairing = PhoneLinkPairing()
        let server = PhoneLinkServer(
            pairing: pairing,
            registry: registry,
            hostProvider: { [] },
            getSnapshot: { nil },
            refreshAndGetSnapshot: { nil }
        )

        do {
            _ = try await server.start(port: 0)
            XCTFail("Expected a fail-closed start")
        } catch {
            XCTAssertEqual(error.localizedDescription, "no private network")
        }
    }

    @MainActor
    func testWindowControllerShowOpensFreshPairingWindow() throws {
        let pairing = PhoneLinkPairing()
        pairing.lastPaired = PairedDevice(
            deviceId: "A",
            name: "A",
            platform: "ios",
            pairedAt: Date(),
            lastSeenAt: Date(),
            lastSeenIP: "192.168.1.1"
        )
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let registry = PhoneLinkRegistry(directory: directory, secretStore: InMemoryPhoneLinkSecretStore())
        defer { try? FileManager.default.removeItem(at: directory) }

        PhoneLinkWindowController.shared.show(
            pairing: pairing,
            registry: registry,
            port: 8788,
            serverStatus: PhoneLinkServerStatus()
        )

        XCTAssertNil(pairing.lastPaired)
        XCTAssertTrue(pairing.isOpen)
        XCTAssertEqual(pairing.currentCode?.count, 32)
        PhoneLinkWindowController.shared.close()
        XCTAssertFalse(pairing.isOpen)
        XCTAssertNil(pairing.currentCode)
    }

    @MainActor
    func testSnapshotNilEncoding() throws {
        let snapshot = PhoneLinkSnapshot(
            server: PhoneLinkSnapshot.ServerInfo(name: "Test", version: "1.0", generatedAt: "now", demo: false),
            providers: [
                PhoneLinkSnapshot.Provider(
                    id: "p1",
                    displayName: "P1",
                    fidelity: "high",
                    status: PhoneLinkSnapshot.Status(kind: "ok", since: nil, why: nil),
                    windows: [PhoneLinkSnapshot.Window(
                        id: "w1", label: "W1", usedFraction: nil, remaining: nil, used: nil, resetsAt: nil
                    )],
                    headlineId: nil,
                    block: nil,
                    account: nil
                )
            ],
            sessions: [PhoneLinkSnapshot.Session(
                id: "s1", name: "S1", detail: "D1", state: "S", waitingFor: nil, since: nil
            )]
        )
        let json = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        for key in ["headlineId", "block", "account", "usedFraction", "remaining", "resetsAt", "waitingFor", "since"] {
            XCTAssertTrue(json.contains("\"\(key)\":null"))
        }
    }

    private struct ServerContext {
        let directory: URL
        let registry: PhoneLinkRegistry
        let pairing: PhoneLinkPairing
        let secrets: InMemoryPhoneLinkSecretStore
        let server: PhoneLinkServer
        let port: Int

        func cleanup() {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    @MainActor
    private func makeServer(snapshot: Data = Data("{}".utf8)) async throws -> ServerContext {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let secrets = InMemoryPhoneLinkSecretStore()
        let registry = PhoneLinkRegistry(directory: directory, secretStore: secrets)
        let pairing = PhoneLinkPairing()
        let server = PhoneLinkServer(
            pairing: pairing,
            registry: registry,
            hostProvider: { ["192.168.255.254"] },
            getSnapshot: { snapshot },
            refreshAndGetSnapshot: { snapshot }
        )
        let port = try await server.start(port: 0)
        return ServerContext(
            directory: directory,
            registry: registry,
            pairing: pairing,
            secrets: secrets,
            server: server,
            port: port
        )
    }

    private func waitForRegistryWrites() {
        let expectation = expectation(description: "registry write")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) { expectation.fulfill() }
        wait(for: [expectation], timeout: 1)
    }
}
