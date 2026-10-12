import SwiftUI
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers

struct PhoneLinkPairingView: View {
    @ObservedObject var pairing: PhoneLinkPairing
    @ObservedObject var registry: PhoneLinkRegistry
    let port: Int
    @ObservedObject var serverStatus: PhoneLinkServerStatus
    
    @State private var copied = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    private var advertisedPort: Int {
        if case .ready(let boundPort) = serverStatus.state { return boundPort }
        return port
    }
    
    var link: String {
        let hosts = PhoneLinkNetwork.getHosts().joined(separator: ",")
        let name = PhoneLinkNetwork.getComputerName()
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.~"))
        let encodedName = name.addingPercentEncoding(withAllowedCharacters: allowed) ?? name
        return "codenotch://pair?v=3&h=\(hosts)&p=\(String(advertisedPort))&c=\(pairing.currentCode ?? "")&n=\(encodedName)"
    }
    
    var body: some View {
        VStack(spacing: 16) {
            if let pd = pairing.lastPaired {
                Image(systemName: "checkmark.circle.fill")
                    .resizable()
                    .foregroundColor(.green)
                    .frame(width: 80, height: 80)
                    .transition(.opacity)
                
                Text(L10n.t("\(pd.name) is connected"))
                    .font(.headline)
                
                Button(L10n.t("Done")) {
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut(.defaultAction)
                
                Button(L10n.t("Connect another phone")) {
                    pairing.lastPaired = nil
                    pairing.openWindow()
                }
                .buttonStyle(.link)
            } else {
                let hosts = PhoneLinkNetwork.getHosts()
                let hasIP = hosts.first(where: { PhoneLinkNetwork.isPrivateIPv4($0) }) != nil
                
                if !hasIP || serverStatus.state == .off || isFailed(serverStatus.state) {
                    Text(L10n.t("Connect your phone"))
                        .font(.headline)
                    Text(L10n.t("This Mac isn't on a local network"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    if case .failed(let err) = serverStatus.state {
                        Text(err).foregroundColor(.red)
                    }
                    
                    Button(L10n.t("Retry")) {
                        pairing.openWindow()
                    }
                } else if !pairing.isOpen {
                    Text(L10n.t("Pairing code expired"))
                        .font(.headline)
                    Button(L10n.t("Generate a new code")) {
                        pairing.openWindow()
                    }
                } else {
                    Text(L10n.t("Connect your phone"))
                        .font(.headline)
                    Text(L10n.t("Scan this code with the Codenotch app on your phone."))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Image(nsImage: generateQRCode(from: link))
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 220, height: 220)
                        .padding(12)
                        .background(Color.white)
                        .cornerRadius(12)
                        .transition(.opacity)
                        .id(pairing.currentCode)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: pairing.currentCode)
                    
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        let diff = max(0, pairing.expiresAt?.timeIntervalSinceNow ?? 0)
                        let min = Int(diff) / 60
                        let sec = Int(diff) % 60
                        Text(L10n.t("Expires in \(String(format: "%d:%02d", min, sec))"))
                            .font(.system(.body, design: .monospaced))
                    }
                    
                    HStack {
                        Text(link)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        
                        Button(copied ? L10n.t("Copied ✓") : L10n.t("Copy Link")) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(link, forType: .string)
                            copied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                        }
                    }
                    .padding(.horizontal)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.t("1. Open Codenotch on your phone"))
                        Text(L10n.t("2. Tap Scan QR Code"))
                        Text(L10n.t("3. Point your phone at this code"))
                    }
                    .font(.footnote)
                    .padding(.top, 8)
                    
                    Text(L10n.t("Your phone must be on the same Wi-Fi as this Mac."))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .frame(width: 380)
    }
    
    private func isFailed(_ state: PhoneLinkServerState) -> Bool {
        if case .failed = state { return true }
        return false
    }
    
    private func generateQRCode(from string: String) -> NSImage {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        
        if let outputImage = filter.outputImage,
           let cgImage = context.createCGImage(outputImage, from: outputImage.extent) {
            return NSImage(cgImage: cgImage, size: NSSize(width: outputImage.extent.width, height: outputImage.extent.height))
        }
        return NSImage()
    }
}
