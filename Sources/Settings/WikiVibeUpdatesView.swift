import SwiftUI

struct WikiVibeUpdatesView: View {
    @ObservedObject var updater: Updater

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(L10n.t("App updates"), systemImage: "arrow.triangle.2.circlepath")
                    .font(.headline)
                Spacer()
                Text(Updater.versionLabel(display: updater.currentVersion, build: updater.currentBuild))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let prompt = updater.prompt {
                switch prompt.phase {
                case .available:
                    HStack {
                        Text(L10n.t("Version \(prompt.version) is available."))
                        Spacer()
                        Button(L10n.t("Update")) { updater.installUpdate() }
                            .buttonStyle(SettingsButtonStyle(kind: .prominent, dashboard: true))
                            .accessibilityIdentifier("updates.install")
                    }
                case .downloading(let fraction):
                    Text(L10n.t("Downloading…"))
                    if let fraction { ProgressView(value: fraction) } else { ProgressView().controlSize(.small) }
                case .extracting(let fraction):
                    Text(L10n.t("Preparing…"))
                    ProgressView(value: fraction)
                case .installing:
                    Text(L10n.t("Installing…"))
                    ProgressView().controlSize(.small)
                }
            } else if let pending = updater.pending {
                HStack {
                    Text(L10n.t("Version \(pending) is available."))
                    Spacer()
                    Button(L10n.t("Update")) { updater.installUpdate() }
                        .buttonStyle(SettingsButtonStyle(kind: .prominent, dashboard: true))
                        .disabled(!updater.canCheck)
                        .accessibilityIdentifier("updates.install")
                }
            } else if let message = updater.outcome.message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            HStack {
                Toggle(L10n.t("Check for updates automatically"), isOn: Binding(
                    get: { updater.automatic }, set: { updater.automatic = $0 }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                Spacer()
                Button(L10n.t("Check now")) { updater.checkNow() }
                    .disabled(!updater.canCheck)
                    .accessibilityIdentifier("updates.check")
            }
            Text(L10n.t("Checks every six hours. Installs only when you choose Update, then restarts WikiVibe."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.10)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("updates.panel")
    }
}
