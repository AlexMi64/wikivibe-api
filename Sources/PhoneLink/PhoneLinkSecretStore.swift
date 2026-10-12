import Foundation

protocol PhoneLinkSecretStore: AnyObject {
    func read(deviceId: String) -> Data?
    @discardableResult func store(_ secret: Data, deviceId: String) -> Bool
    @discardableResult func remove(deviceId: String) -> Bool
}

final class PhoneLinkKeychainSecretStore: PhoneLinkSecretStore {
    static let service = "com.codenotch.phonelink.device"

    func read(deviceId: String) -> Data? {
        guard let value = KeychainItem.read(service: Self.service, account: deviceId) else {
            return nil
        }
        return Data(hexString: value)
    }

    func store(_ secret: Data, deviceId: String) -> Bool {
        KeychainItem.store(service: Self.service, account: deviceId, value: secret.hexString)
    }

    func remove(deviceId: String) -> Bool {
        KeychainItem.delete(service: Self.service, account: deviceId)
    }
}

final class InMemoryPhoneLinkSecretStore: PhoneLinkSecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var secrets: [String: Data] = [:]

    func read(deviceId: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return secrets[deviceId]
    }

    func store(_ secret: Data, deviceId: String) -> Bool {
        lock.lock()
        secrets[deviceId] = secret
        lock.unlock()
        return true
    }

    func remove(deviceId: String) -> Bool {
        lock.lock()
        let existed = secrets.removeValue(forKey: deviceId) != nil
        lock.unlock()
        return existed
    }
}
