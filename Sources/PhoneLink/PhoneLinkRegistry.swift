import Foundation

struct PairedDevice: Codable, Identifiable, Equatable, Sendable {
    let deviceId: String
    var name: String
    var platform: String
    let pairedAt: Date
    var lastSeenAt: Date
    var lastSeenIP: String
    
    var id: String { deviceId }
}

final class PhoneLinkRegistry: ObservableObject, @unchecked Sendable {
    @Published private(set) var devices: [PairedDevice] = []
    @Published private(set) var discardedLegacyDevices = false
    
    private let url: URL
    private let secretStore: PhoneLinkSecretStore
    private let queue = DispatchQueue(label: "PhoneLinkRegistry")
    private var lastWrite: Date = Date.distantPast
    private var pendingWrite = false
    private let lock = NSLock()
    private var backingDevices: [PairedDevice] = [] {
        didSet {
            let copy = backingDevices
            DispatchQueue.main.async {
                self.devices = copy
            }
        }
    }
    private var secrets: [String: Data] = [:]
    
    init(directory: URL, secretStore: PhoneLinkSecretStore = PhoneLinkKeychainSecretStore()) {
        let dir = directory
        self.url = dir.appendingPathComponent("devices.json")
        self.secretStore = secretStore
        
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch {
            print("Failed to create phone-link directory: \(error)")
        }
        
        load()
    }
    
    private func load() {
        guard let data = try? Data(contentsOf: url),
              let records = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }

        var decoded: [PairedDevice] = []
        var discardedLegacy = false
        for record in records {
            if record["secret"] != nil {
                discardedLegacy = true
                continue
            }
            guard JSONSerialization.isValidJSONObject(record),
                  let recordData = try? JSONSerialization.data(withJSONObject: record),
                  let device = try? JSONDecoder().decode(PairedDevice.self, from: recordData) else {
                continue
            }
            decoded.append(device)
            if let secret = secretStore.read(deviceId: device.deviceId) {
                secrets[device.deviceId] = secret
            }
        }
        lock.lock()
        backingDevices = decoded
        lock.unlock()
        discardedLegacyDevices = discardedLegacy
        if discardedLegacy {
            performSave(decoded)
        }
    }
    
    private func saveImmediate() {
        queue.async {
            self.lock.lock()
            let currentDevices = self.backingDevices
            self.lock.unlock()
            
            self.performSave(currentDevices)
            self.pendingWrite = false
        }
    }
    
    private func scheduleThrottledSave() {
        queue.async {
            let now = Date()
            if now.timeIntervalSince(self.lastWrite) < 60 {
                if !self.pendingWrite {
                    self.pendingWrite = true
                    self.queue.asyncAfter(deadline: .now() + 60) {
                        if !self.pendingWrite { return } // might have been saved immediately
                        self.pendingWrite = false
                        self.lock.lock()
                        let latestDevices = self.backingDevices
                        self.lock.unlock()
                        self.performSave(latestDevices)
                    }
                }
                return
            }
            self.lock.lock()
            let latestDevices = self.backingDevices
            self.lock.unlock()
            self.performSave(latestDevices)
        }
    }
    
    private func performSave(_ devicesToSave: [PairedDevice]) {
        lastWrite = Date()
        do {
            let data = try JSONEncoder().encode(devicesToSave)
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            print("Failed to save devices: \(error)")
        }
    }
    
    func addOrUpdate(device: PairedDevice, immediate: Bool = true) {
        lock.lock()
        if let index = backingDevices.firstIndex(where: { $0.deviceId == device.deviceId }) {
            backingDevices[index] = device
        } else {
            backingDevices.append(device)
        }
        lock.unlock()
        
        if immediate {
            saveImmediate()
        } else {
            scheduleThrottledSave()
        }
    }

    @discardableResult
    func addOrUpdate(device: PairedDevice, secret: Data) -> Bool {
        guard secretStore.store(secret, deviceId: device.deviceId) else { return false }
        lock.lock()
        secrets[device.deviceId] = secret
        lock.unlock()
        addOrUpdate(device: device)
        return true
    }
    
    func remove(deviceId: String) {
        lock.lock()
        backingDevices.removeAll { $0.deviceId == deviceId }
        secrets.removeValue(forKey: deviceId)
        lock.unlock()
        secretStore.remove(deviceId: deviceId)
        saveImmediate()
    }
    
    func getDevice(id: String) -> PairedDevice? {
        lock.lock()
        defer { lock.unlock() }
        return backingDevices.first { $0.deviceId == id }
    }

    func secret(deviceId: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return secrets[deviceId]
    }
}
