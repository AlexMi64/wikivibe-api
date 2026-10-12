import CryptoKit
import Foundation
import NIOCore
import NIOHTTP1

actor SecurityStore {
    private var nonces: [String: [String: Date]] = [:]
    private var pairRequests: [String: [Date]] = [:]
    private var apiRequests: [String: [Date]] = [:]

    func checkAndStoreNonce(key: String, nonce: String) -> Bool {
        cleanup()
        var values = nonces[key] ?? [:]
        if values[nonce] != nil { return false }
        values[nonce] = Date().addingTimeInterval(300)
        nonces[key] = values
        return true
    }

    func checkPairRateLimit(ip: String) -> Bool {
        cleanup()
        var requests = pairRequests[ip] ?? []
        requests.append(Date())
        pairRequests[ip] = requests
        return requests.count <= 10
    }

    func checkAPIRateLimit(ip: String) -> Bool {
        cleanup()
        var requests = apiRequests[ip] ?? []
        requests.append(Date())
        apiRequests[ip] = requests
        return requests.count <= 120
    }

    private func cleanup() {
        let now = Date()
        for key in nonces.keys {
            nonces[key] = nonces[key]?.filter { $0.value > now }
            if nonces[key]?.isEmpty == true { nonces.removeValue(forKey: key) }
        }
        for ip in pairRequests.keys {
            pairRequests[ip] = pairRequests[ip]?.filter { now.timeIntervalSince($0) < 60 }
            if pairRequests[ip]?.isEmpty == true { pairRequests.removeValue(forKey: ip) }
        }
        for ip in apiRequests.keys {
            apiRequests[ip] = apiRequests[ip]?.filter { now.timeIntervalSince($0) < 60 }
            if apiRequests[ip]?.isEmpty == true { apiRequests.removeValue(forKey: ip) }
        }
    }
}

final class PhoneLinkRequestHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart

    private static let maximumEnvelopeBytes = 64 * 1024

    private let pairing: PhoneLinkPairing
    private let registry: PhoneLinkRegistry
    private let securityStore: SecurityStore
    private let getSnapshot: @Sendable () async -> Data?
    private let refreshAndGetSnapshot: @Sendable () async -> Data?

    private var head: HTTPRequestHead?
    private var body = Data()
    private var rejectedRequest = false

    init(
        pairing: PhoneLinkPairing,
        registry: PhoneLinkRegistry,
        securityStore: SecurityStore,
        getSnapshot: @escaping @Sendable () async -> Data?,
        refreshAndGetSnapshot: @escaping @Sendable () async -> Data?
    ) {
        self.pairing = pairing
        self.registry = registry
        self.securityStore = securityStore
        self.getSnapshot = getSnapshot
        self.refreshAndGetSnapshot = refreshAndGetSnapshot
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let request):
            head = request
            body = Data()
            rejectedRequest = false
        case .body(var buffer):
            guard !rejectedRequest else { return }
            guard body.count + buffer.readableBytes <= Self.maximumEnvelopeBytes else {
                rejectedRequest = true
                fail(
                    context.channel,
                    status: .payloadTooLarge,
                    jsonBody: Data("{\"error\":\"payload-too-large\"}".utf8)
                )
                return
            }
            if let bytes = buffer.readBytes(length: buffer.readableBytes) {
                body.append(contentsOf: bytes)
            }
        case .end:
            guard !rejectedRequest, let requestHead = head else {
                head = nil
                body = Data()
                return
            }
            let requestBody = body
            head = nil
            body = Data()
            handleRequest(channel: context.channel, head: requestHead, bodyData: requestBody)
        }
    }

    private func handleRequest(channel: Channel, head: HTTPRequestHead, bodyData: Data) {
        guard let ip = extractIP(channel.remoteAddress) else {
            fail(channel, status: .forbidden)
            return
        }
        guard PhoneLinkNetwork.isPrivateIP(ip) else {
            fail(channel, status: .forbidden, jsonBody: Data("{\"error\":\"local-network-only\"}".utf8))
            return
        }

        let path = head.uri.components(separatedBy: "?").first ?? "/"
        if head.method == .GET, path == "/health" {
            let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
            respondPlaintext(
                channel,
                jsonBody: Data("{\"ok\":true,\"app\":\"codenotch\",\"api\":3,\"version\":\"\(version)\"}".utf8)
            )
            return
        }

        if head.method == .POST, path == "/api/v3/pair" {
            Task {
                await handlePair(channel: channel, head: head, bodyData: bodyData, ip: ip)
            }
            return
        }

        let isSnapshot = head.method == .GET && path == "/api/v3/snapshot"
        let isRefresh = head.method == .POST && path == "/api/v3/refresh"
        guard isSnapshot || isRefresh else {
            fail(channel, status: .notFound)
            return
        }
        Task {
            await handleAPI(channel: channel, head: head, path: path, bodyData: bodyData, ip: ip, refresh: isRefresh)
        }
    }

    private func handlePair(channel: Channel, head: HTTPRequestHead, bodyData: Data, ip: String) async {
        let codes = await pairing.authenticationCodes()
        guard let activeCode = codes.active else {
            fail(channel, status: .forbidden, jsonBody: Data("{\"error\":\"pairing-closed\"}".utf8))
            return
        }

        guard await securityStore.checkPairRateLimit(ip: ip) else {
            fail(channel, status: .tooManyRequests, jsonBody: Data("{\"error\":\"rate-limited\"}".utf8))
            return
        }
        guard let headers = authenticatedHeaders(head) else {
            fail(channel, status: .unauthorized)
            return
        }
        guard timestampIsCurrent(headers.timestamp) else {
            clockSkew(channel)
            return
        }
        guard await securityStore.checkAndStoreNonce(key: "pair:\(ip)", nonce: headers.nonce) else {
            fail(channel, status: .unauthorized, jsonBody: Data("{\"error\":\"replayed-nonce\"}".utf8))
            return
        }

        let activeKeys: PhoneLinkCrypto.PairingKeys
        do {
            activeKeys = try PhoneLinkCrypto.pairingKeys(code: activeCode)
        } catch {
            fail(channel, status: .internalServerError)
            return
        }

        let actualSignature = PhoneLinkCrypto.signature(
            key: activeKeys.signature,
            ts: headers.timestamp,
            nonce: headers.nonce,
            method: head.method.rawValue,
            uri: head.uri,
            bodyAsSent: bodyData
        )
        if !PhoneLinkCrypto.constantTimeEqual(headers.signature, actualSignature) {
            for retiredCode in codes.retired {
                guard let retiredKeys = try? PhoneLinkCrypto.pairingKeys(code: retiredCode) else { continue }
                let retiredSignature = PhoneLinkCrypto.signature(
                    key: retiredKeys.signature,
                    ts: headers.timestamp,
                    nonce: headers.nonce,
                    method: head.method.rawValue,
                    uri: head.uri,
                    bodyAsSent: bodyData
                )
                if PhoneLinkCrypto.constantTimeEqual(headers.signature, retiredSignature) {
                    fail(channel, status: .unauthorized, jsonBody: Data("{\"error\":\"code-expired\"}".utf8))
                    return
                }
            }
            fail(channel, status: .unauthorized, jsonBody: Data("{\"error\":\"bad-code\"}".utf8))
            return
        }

        let plaintext: Data
        do {
            plaintext = try PhoneLinkCrypto.open(
                bodyData,
                key: activeKeys.encryption,
                aad: PhoneLinkCrypto.pairingRequestAAD(
                    ts: headers.timestamp,
                    nonce: headers.nonce,
                    deviceId: headers.deviceId
                )
            )
        } catch {
            fail(channel, status: .unauthorized, jsonBody: Data("{\"error\":\"bad-code\"}".utf8))
            return
        }

        struct PairRequest: Decodable {
            let deviceId: String
            let name: String
            let platform: String
        }
        guard let request = try? JSONDecoder().decode(PairRequest.self, from: plaintext),
              request.deviceId == headers.deviceId else {
            fail(channel, status: .badRequest)
            return
        }
        guard await pairing.consume(code: activeCode) else {
            fail(channel, status: .forbidden, jsonBody: Data("{\"error\":\"pairing-closed\"}".utf8))
            return
        }

        let secret: Data
        do {
            secret = try PhoneLinkCrypto.deviceSecret(code: activeCode, deviceId: request.deviceId)
        } catch {
            fail(channel, status: .internalServerError)
            return
        }
        let device = PairedDevice(
            deviceId: request.deviceId,
            name: request.name,
            platform: request.platform,
            pairedAt: Date(),
            lastSeenAt: Date(),
            lastSeenIP: ip
        )
        guard registry.addOrUpdate(device: device, secret: secret) else {
            fail(channel, status: .internalServerError)
            return
        }

        await MainActor.run { pairing.lastPaired = device }
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
        struct PairResponse: Encodable {
            let paired: Bool
            let server: String
            let version: String
            let api: Int
            let deviceId: String
        }
        guard let responseJSON = try? JSONEncoder().encode(PairResponse(
            paired: true,
            server: PhoneLinkNetwork.getComputerName(),
            version: version,
            api: 3,
            deviceId: request.deviceId
        )) else {
            fail(channel, status: .internalServerError)
            return
        }
        respondEncrypted(
            channel,
            plaintext: responseJSON,
            key: activeKeys.encryption,
            aad: PhoneLinkCrypto.pairingResponseAAD(
                ts: headers.timestamp,
                nonce: headers.nonce,
                deviceId: request.deviceId,
                status: 200
            )
        )
    }

    private func handleAPI(
        channel: Channel,
        head: HTTPRequestHead,
        path: String,
        bodyData: Data,
        ip: String,
        refresh: Bool
    ) async {
        guard await securityStore.checkAPIRateLimit(ip: ip) else {
            fail(channel, status: .tooManyRequests, jsonBody: Data("{\"error\":\"rate-limited\"}".utf8))
            return
        }
        guard let requestedDeviceId = head.headers["x-cn-device"].first, !requestedDeviceId.isEmpty else {
            fail(channel, status: .unauthorized, jsonBody: Data("{\"error\":\"unknown-device\"}".utf8))
            return
        }
        guard let headers = authenticatedHeaders(head) else {
            fail(channel, status: .unauthorized)
            return
        }
        guard timestampIsCurrent(headers.timestamp) else {
            clockSkew(channel)
            return
        }
        guard let device = registry.getDevice(id: requestedDeviceId),
              let secret = registry.secret(deviceId: requestedDeviceId) else {
            fail(channel, status: .unauthorized, jsonBody: Data("{\"error\":\"unknown-device\"}".utf8))
            return
        }
        guard await securityStore.checkAndStoreNonce(key: "device:\(headers.deviceId)", nonce: headers.nonce) else {
            fail(channel, status: .unauthorized, jsonBody: Data("{\"error\":\"replayed-nonce\"}".utf8))
            return
        }

        let keys = PhoneLinkCrypto.deviceKeys(secret: secret)
        let expectedSignature = PhoneLinkCrypto.signature(
            key: keys.signature,
            ts: headers.timestamp,
            nonce: headers.nonce,
            method: head.method.rawValue,
            uri: head.uri,
            bodyAsSent: bodyData
        )
        guard PhoneLinkCrypto.constantTimeEqual(headers.signature, expectedSignature) else {
            fail(channel, status: .unauthorized, jsonBody: Data("{\"error\":\"bad-signature\"}".utf8))
            return
        }
        if !bodyData.isEmpty {
            do {
                _ = try PhoneLinkCrypto.open(
                    bodyData,
                    key: keys.encryption,
                    aad: PhoneLinkCrypto.requestAAD(
                        ts: headers.timestamp,
                        nonce: headers.nonce,
                        method: head.method.rawValue,
                        path: path,
                        deviceId: headers.deviceId
                    )
                )
            } catch {
                fail(channel, status: .unauthorized, jsonBody: Data("{\"error\":\"bad-signature\"}".utf8))
                return
            }
        }

        var updatedDevice = device
        updatedDevice.lastSeenAt = Date()
        updatedDevice.lastSeenIP = ip
        registry.addOrUpdate(device: updatedDevice, immediate: false)

        let snapshot = refresh ? await refreshAndGetSnapshot() : await getSnapshot()
        guard let snapshot else {
            fail(channel, status: .internalServerError)
            return
        }
        respondEncrypted(
            channel,
            plaintext: snapshot,
            key: keys.encryption,
            aad: PhoneLinkCrypto.responseAAD(
                ts: headers.timestamp,
                nonce: headers.nonce,
                method: head.method.rawValue,
                path: path,
                deviceId: headers.deviceId,
                status: 200
            )
        )
    }

    private struct AuthenticatedHeaders {
        let timestamp: String
        let nonce: String
        let deviceId: String
        let signature: Data
    }

    private func authenticatedHeaders(_ head: HTTPRequestHead) -> AuthenticatedHeaders? {
        guard let timestamp = head.headers["x-cn-timestamp"].first,
              Int64(timestamp) != nil,
              let nonce = head.headers["x-cn-nonce"].first,
              Data(hexString: nonce)?.count == 16,
              let deviceId = head.headers["x-cn-device"].first,
              !deviceId.isEmpty,
              let signatureHex = head.headers["x-cn-signature"].first,
              let signature = Data(hexString: signatureHex),
              signature.count == 32 else {
            return nil
        }
        return AuthenticatedHeaders(
            timestamp: timestamp,
            nonce: nonce,
            deviceId: deviceId,
            signature: signature
        )
    }

    private func timestampIsCurrent(_ timestamp: String) -> Bool {
        guard let value = Int64(timestamp) else { return false }
        let now = Int64(Date().timeIntervalSince1970)
        return value >= now - 120 && value <= now + 120
    }

    private func clockSkew(_ channel: Channel) {
        let now = Int(Date().timeIntervalSince1970)
        fail(
            channel,
            status: .unauthorized,
            jsonBody: Data("{\"error\":\"clock-skew\",\"serverTime\":\(now)}".utf8)
        )
    }

    private func extractIP(_ address: SocketAddress?) -> String? {
        guard let address else { return nil }
        switch address {
        case .v4(let value): return value.host
        case .v6(let value): return value.host
        case .unixDomainSocket: return nil
        }
    }

    private func fail(_ channel: Channel, status: HTTPResponseStatus, jsonBody: Data? = nil) {
        respond(channel, status: status, contentType: "application/json", body: jsonBody)
    }

    private func respondPlaintext(_ channel: Channel, status: HTTPResponseStatus = .ok, jsonBody: Data) {
        respond(channel, status: status, contentType: "application/json", body: jsonBody)
    }

    private func respondEncrypted(_ channel: Channel, plaintext: Data, key: SymmetricKey, aad: Data) {
        do {
            let envelope = try PhoneLinkCrypto.seal(plaintext, key: key, aad: aad)
            respond(channel, status: .ok, contentType: "application/codenotch-v3", body: envelope)
        } catch {
            fail(channel, status: .internalServerError)
        }
    }

    private func respond(
        _ channel: Channel,
        status: HTTPResponseStatus,
        contentType: String,
        body: Data?
    ) {
        channel.eventLoop.execute {
            var headers = HTTPHeaders([
                ("content-type", contentType),
                ("connection", "close")
            ])
            if let body { headers.add(name: "content-length", value: String(body.count)) }
            let head = HTTPResponseHead(version: .http1_1, status: status, headers: headers)
            channel.write(NIOAny(HTTPServerResponsePart.head(head)), promise: nil)
            if let body {
                var buffer = channel.allocator.buffer(capacity: body.count)
                buffer.writeBytes(body)
                channel.write(NIOAny(HTTPServerResponsePart.body(.byteBuffer(buffer))), promise: nil)
            }
            channel.writeAndFlush(NIOAny(HTTPServerResponsePart.end(nil))).whenComplete { _ in
                channel.close(promise: nil)
            }
        }
    }
}
