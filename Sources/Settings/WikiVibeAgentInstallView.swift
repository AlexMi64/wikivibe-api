import SwiftUI

struct WikiVibeAgentInstallView: View {
    @ObservedObject var auth: WikiVibeAuthCoordinator
    @ObservedObject var model: WikiVibeKeysController
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(L10n.t("Install agents with WikiVibe"), systemImage: "square.and.arrow.down")
                    .font(.subheadline.bold())
                Spacer()
                Button { model.refreshInstallations() } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel(L10n.t("Refresh"))
                    .disabled(model.isBusy)
            }
            Text(L10n.t("Install an agent, then configure WikiVibe with the selected key and its available models. Nothing runs before confirmation."))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let key = model.selectedKey {
                Label(key.displayName.isEmpty ? L10n.t("Key #\(key.id)") : key.displayName, systemImage: "key")
                    .font(.caption).foregroundStyle(.purple)
            }
            ForEach(WikiVibeAgent.allCases) { agent in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: "terminal").font(.title3).foregroundStyle(.cyan)
                            .frame(width: 30, height: 30)
                            .background(.cyan.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(agent.title).font(.callout.weight(.semibold))
                            Text(model.installedAgents.contains(agent) ? L10n.t("Installed") : L10n.t("Not installed"))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        Link(destination: agent.homepage) { Image(systemName: "arrow.up.right.square") }
                            .help(L10n.t("Official installation instructions"))
                    }
                    Button {
                        Task { await model.prepare(auth: auth, installing: agent) }
                    } label: {
                        Label(model.installedAgents.contains(agent) ? L10n.t("Configure with selected key…") : L10n.t("Install and configure…"),
                              systemImage: model.installedAgents.contains(agent) ? "key.fill" : "arrow.down.circle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(SettingsButtonStyle(dashboard: true))
                    .disabled(model.isBusy || model.selectedKey?.isUsable != true || !agent.supports(model.selectedKey?.protocols) || WikiVibeAgentService.nodeURL == nil)
                    .accessibilityIdentifier("agents.install.\(agent.rawValue)")
                    if !agent.supports(model.selectedKey?.protocols) {
                        Text(L10n.t("Protocol not allowed")).font(.caption2).foregroundStyle(.orange)
                    }
                }
                .padding(10)
                .background(AccountControlPalette.surface(colorScheme), in: RoundedRectangle(cornerRadius: 10))
            }
            Text(L10n.t("Installers download third-party software. The API key is passed only to the configuration adapter, never to the installer. No administrator password is requested."))
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(.cyan.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.cyan.opacity(0.16)))
        .accessibilityIdentifier("agents.install.panel")
        .onAppear { model.refreshInstallations() }
    }
}
