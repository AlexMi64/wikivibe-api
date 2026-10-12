import Foundation
import Combine
import Security

@MainActor
final class PhoneLinkPairing: ObservableObject {
    @Published private(set) var currentCode: String?
    @Published private(set) var expiresAt: Date?
    @Published private(set) var isOpen = false
    private(set) var retiredCodes: [String: Date] = [:]
    private var timer: Timer?

    struct AuthenticationCodes {
        let active: String?
        let retired: [String]
    }

    func openWindow() {
        if let currentCode {
            retiredCodes[currentCode] = Date()
        }
        cleanRetiredCodes()

        var bytes = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            closeWindow()
            return
        }
        currentCode = bytes.map { String(format: "%02x", $0) }.joined()
        expiresAt = Date().addingTimeInterval(300)
        isOpen = true

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.closeWindow()
            }
        }
    }

    func closeWindow() {
        if let currentCode {
            retiredCodes[currentCode] = Date()
        }
        timer?.invalidate()
        timer = nil
        currentCode = nil
        expiresAt = nil
        isOpen = false
        cleanRetiredCodes()
    }

    func checkCode(_ code: String) -> CodeStatus {
        if isOpen, code == currentCode, let expiresAt, Date() < expiresAt {
            return .valid
        }

        cleanRetiredCodes()
        if retiredCodes.keys.contains(code) {
            return .expired
        }
        return .invalid
    }
    
    private func cleanRetiredCodes() {
        let now = Date()
        retiredCodes = retiredCodes.filter { now.timeIntervalSince($0.value) < 600 }

        if retiredCodes.count > 8 {
            let sorted = retiredCodes.sorted { $0.value > $1.value }
            retiredCodes = Dictionary(uniqueKeysWithValues: sorted.prefix(8).map { ($0.key, $0.value) })
        }
    }
    
    @Published var lastPaired: PairedDevice?

    func authenticationCodes() -> AuthenticationCodes {
        if isOpen, let expiresAt, Date() >= expiresAt {
            closeWindow()
        } else {
            cleanRetiredCodes()
        }
        return AuthenticationCodes(active: isOpen ? currentCode : nil, retired: Array(retiredCodes.keys))
    }

    func consume(code: String) -> Bool {
        guard isOpen, let expiresAt, Date() < expiresAt, currentCode == code else { return false }
        closeWindow()
        return true
    }
}

enum CodeStatus {
    case valid
    case expired
    case invalid
}
