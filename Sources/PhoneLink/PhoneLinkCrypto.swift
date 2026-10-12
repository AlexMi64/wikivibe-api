import CryptoKit
import Foundation
import Security

enum PhoneLinkCrypto {
    struct DeviceKeys {
        let secret: Data
        let signature: SymmetricKey
        let encryption: SymmetricKey
    }

    struct PairingKeys {
        let signature: SymmetricKey
        let encryption: SymmetricKey
    }

    enum CryptoError: Error {
        case invalidCode
        case invalidNonce
        case invalidEnvelope
        case randomGenerationFailed(OSStatus)
    }

    static func deviceSecret(code: String, deviceId: String) throws -> Data {
        guard let codeBytes = Data(hexString: code), codeBytes.count == 16 else {
            throw CryptoError.invalidCode
        }
        let key = SymmetricKey(data: codeBytes)
        return Data(HMAC<SHA256>.authenticationCode(
            for: Data("codenotch-device-v3:\(deviceId)".utf8),
            using: key
        ))
    }

    static func deviceKeys(secret: Data) -> DeviceKeys {
        let material = SymmetricKey(data: secret)
        return DeviceKeys(
            secret: secret,
            signature: derive(material, info: "codenotch/v3/sig"),
            encryption: derive(material, info: "codenotch/v3/enc")
        )
    }

    static func pairingKeys(code: String) throws -> PairingKeys {
        guard let codeBytes = Data(hexString: code), codeBytes.count == 16 else {
            throw CryptoError.invalidCode
        }
        let material = SymmetricKey(data: codeBytes)
        return PairingKeys(
            signature: derive(material, info: "codenotch/v3/pair-sig"),
            encryption: derive(material, info: "codenotch/v3/pair-enc")
        )
    }

    static func keyData(_ key: SymmetricKey) -> Data {
        key.withUnsafeBytes { Data($0) }
    }

    private static func derive(_ material: SymmetricKey, info: String) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: material,
            salt: Data(),
            info: Data(info.utf8),
            outputByteCount: 32
        )
    }

    static func requestAAD(ts: String, nonce: String, method: String, path: String, deviceId: String) -> Data {
        Data("v3|req|\(ts)|\(nonce)|\(method)|\(path)|\(deviceId)".utf8)
    }

    static func responseAAD(ts: String, nonce: String, method: String, path: String, deviceId: String, status: Int) -> Data {
        Data("v3|res|\(ts)|\(nonce)|\(method)|\(path)|\(deviceId)|\(status)".utf8)
    }

    static func pairingRequestAAD(ts: String, nonce: String, deviceId: String) -> Data {
        Data("v3|pair-req|\(ts)|\(nonce)|POST|/api/v3/pair|\(deviceId)".utf8)
    }

    static func pairingResponseAAD(ts: String, nonce: String, deviceId: String, status: Int) -> Data {
        Data("v3|pair-res|\(ts)|\(nonce)|POST|/api/v3/pair|\(deviceId)|\(status)".utf8)
    }

    static func seal(_ plaintext: Data, key: SymmetricKey, aad: Data, nonce: Data? = nil) throws -> Data {
        let nonceData = try nonce ?? randomBytes(count: 12)
        guard nonceData.count == 12 else { throw CryptoError.invalidNonce }
        let gcmNonce = try AES.GCM.Nonce(data: nonceData)
        let box = try AES.GCM.seal(plaintext, using: key, nonce: gcmNonce, authenticating: aad)
        var combined = nonceData
        combined.append(box.ciphertext)
        combined.append(box.tag)
        return Data(combined.base64EncodedString().utf8)
    }

    static func open(_ envelope: Data, key: SymmetricKey, aad: Data) throws -> Data {
        guard let combined = Data(base64Encoded: envelope), combined.count >= 28 else {
            throw CryptoError.invalidEnvelope
        }
        let nonceData = combined.prefix(12)
        let ciphertext = combined.dropFirst(12).dropLast(16)
        let tag = combined.suffix(16)
        let box = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: nonceData),
            ciphertext: ciphertext,
            tag: tag
        )
        return try AES.GCM.open(box, using: key, authenticating: aad)
    }

    static func signature(
        key: SymmetricKey,
        ts: String,
        nonce: String,
        method: String,
        uri: String,
        bodyAsSent: Data
    ) -> Data {
        let bodyHash = Data(SHA256.hash(data: bodyAsSent)).hexString
        let payload = "\(ts).\(nonce).\(method).\(uri).\(bodyHash)"
        return Data(HMAC<SHA256>.authenticationCode(for: Data(payload.utf8), using: key))
    }

    static func signatureHex(
        key: SymmetricKey,
        ts: String,
        nonce: String,
        method: String,
        uri: String,
        bodyAsSent: Data
    ) -> String {
        signature(key: key, ts: ts, nonce: nonce, method: method, uri: uri, bodyAsSent: bodyAsSent).hexString
    }

    static func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }

    static func randomBytes(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else { throw CryptoError.randomGenerationFailed(status) }
        return Data(bytes)
    }
}

extension Data {
    init?(hexString: String) {
        guard hexString.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hexString.count / 2)
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self = Data(bytes)
    }

    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
