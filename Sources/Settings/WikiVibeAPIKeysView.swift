import SwiftUI

struct WikiVibeAPIKeysView: View {
    @ObservedObject var auth: WikiVibeAuthCoordinator
    @StateObject private var model = WikiVibeKeysController()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if auth.account == nil {
                Text(L10n.t("Sign in to load API keys from your account.")).foregroundStyle(.secondary)
            } else {
                keyControls
                Divider()
                agentControls
                if let error = model.error {
                    Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                        .accessibilityIdentifier("keys.error")
                }
                if let result = model.result { resultView(result) }
            }
        }
        .task(id: auth.account?.id) { await model.load(auth: auth) }
        .onDisappear { model.clear() }
        .sheet(isPresented: Binding(get: { model.preview != nil }, set: { if !$0 { model.cancelPreview() } })) {
            if let preview = model.preview { previewView(preview) }
        }
    }

    private var keyControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.t("Account keys")).font(.subheadline.weight(.medium))
                Spacer()
                if model.isBusy { ProgressView().controlSize(.small) }
                Button { Task { await model.load(auth: auth) } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help(L10n.t("Reload API keys"))
                .accessibilityLabel(L10n.t("Reload API keys"))
                .accessibilityIdentifier("keys.reload")
                .disabled(model.isBusy)
            }
            if model.hasLoaded && !model.keys.isEmpty {
                Text(L10n.t("API keys loaded: \(model.keys.count)")).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("keys.loaded")
            }
            if model.hasLoaded && model.keys.isEmpty {
                Text(L10n.t("No API keys were found. Create a key in the WikiVibe panel, then reload.")).foregroundStyle(.secondary)
                Link(L10n.t("Open WikiVibe panel"), destination: WikiVibeAuthContract.api.appendingPathComponent("keys"))
            }
            Picker(L10n.t("API key"), selection: $model.selectedKeyID) {
                Text(L10n.t("Choose an API key")).tag(nil as Int?)
                ForEach(model.keys) { key in
                    Text(key.displayName.isEmpty ? L10n.t("Key #\(key.id)") : key.displayName)
                        .tag(Optional(key.id)).disabled(!key.isUsable)
                }
            }
            .accessibilityIdentifier("keys.selection")
            if let key = model.selectedKey {
                Text(key.isUsable ? L10n.t("Active key · value hidden") : L10n.t("This key is inactive, expired, or unavailable."))
                    .font(.caption).foregroundStyle(.secondary)
                if let protocols = key.protocols {
                    Text(L10n.t("Allowed protocols: \(protocols.joined(separator: ", "))"))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(L10n.t("This key does not report protocol restrictions. Compatibility must be checked in the agent."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Picker(L10n.t("API base URL"), selection: $model.gateway) {
                ForEach(WikiVibeGateway.allCases) { gateway in Text(gateway.rawValue).tag(gateway) }
            }
            .accessibilityIdentifier("keys.gateway")
            Text(L10n.t("Key values stay in memory. Loading keys and models does not change agent settings or run inference."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .disabled(model.isBusy)
    }

    private var agentControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t("Configure agents")).font(.subheadline.weight(.medium))
            ForEach(WikiVibeAgent.allCases) { agent in
                let supported = agent.supports(model.selectedKey?.protocols)
                Toggle(isOn: Binding(get: { model.agents.contains(agent) && supported }, set: { selected in
                    if selected { model.agents.insert(agent) } else { model.agents.remove(agent) }
                })) {
                    HStack {
                        Text(agent.title)
                        if !supported { Text(L10n.t("Protocol not allowed")).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                .toggleStyle(.checkbox)
                .accessibilityIdentifier("keys.agent.\(agent.rawValue)")
                .disabled(model.isBusy || !supported)
            }
            if WikiVibeAgentService.nodeURL == nil {
                Text(WikiVibeKeysError.nodeMissing.localizedDescription).font(.caption).foregroundStyle(.secondary)
            }
            Button(L10n.t("Load models and preview…")) {
                Task { await model.prepare(auth: auth) }
            }
            .accessibilityIdentifier("keys.preview")
            .disabled(!model.canPreview || WikiVibeAgentService.nodeURL == nil)
            Button(L10n.t("Preview restoring agent backups…")) {
                Task { await model.prepare(auth: auth, restore: true) }
            }
            .font(.caption)
            .accessibilityIdentifier("keys.restore")
            .disabled(model.isBusy || model.agents.isEmpty || WikiVibeAgentService.nodeURL == nil)
        }
    }

    private func previewView(_ report: WikiVibeAgentReport) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.isRestoring ? L10n.t("Restore agent configurations") : L10n.t("Review agent configuration changes"))
                .font(.title2.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !model.isRestoring {
                        Text(model.gateway.rawValue).font(.callout.monospaced())
                        Text(L10n.t("Available models: \(model.models.count)"))
                        DisclosureGroup(L10n.t("View available models")) {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(model.models, id: \.self) { Text($0).font(.caption.monospaced()) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    if report.changes?.isEmpty != false {
                        Text(L10n.t("No files can be changed for this selection.")).foregroundStyle(.secondary)
                    } else {
                        Text(L10n.t("Files to change")).font(.headline)
                        fileRows(report)
                    }
                    failures(report)
                    Divider()
                    Text(L10n.t("The API key will be stored as plain text in agent configuration files. Backups may contain previous keys and other secrets. Files use permissions 0600; backup folders use 0700."))
                    Text(L10n.t("Only standard files in your local home folder are changed. Project settings, environment variables and custom agent homes can override them. Restart the agent after applying. Agent installation is not checked."))
                    if model.isRestoring {
                        Text(L10n.t("Restore returns the original files, or removes files created by WikiVibe. Files edited after applying are not overwritten."))
                    } else {
                        Text(L10n.t("Codex: use codex -p wikivibe, then /model. OpenCode: /models. oh-my-pi: /model; model roles are kept. Current model selections are not switched."))
                        if model.effectiveAgents.contains(.claude) {
                            Text(L10n.t("Claude Code: this replaces the global Anthropic gateway and authentication token. Choose an available model with /model in a new session. The model picker requires Claude Code 2.1.242 or newer."))
                                .foregroundStyle(.orange)
                        }
                        Text(L10n.t("The model list proves access only to the catalog, not support for streaming, tools, reasoning or image generation."))
                    }
                    Text(L10n.t("Each file is written separately. A failure can leave partial changes; review the result and use backups when necessary."))
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            HStack {
                Button(L10n.t("Cancel")) { model.cancelPreview() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(model.isRestoring ? L10n.t("Confirm restore") : L10n.t("Confirm and write files")) {
                    Task { await model.apply(auth: auth) }
                }
                .accessibilityIdentifier("keys.confirm")
                .keyboardShortcut(.defaultAction)
                .disabled(report.changes?.isEmpty != false || model.isBusy)
            }
        }
        .padding(24)
        .frame(minWidth: 420, idealWidth: 600, maxWidth: 700, minHeight: 400, idealHeight: 620)
    }

    private func fileRows(_ report: WikiVibeAgentReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(report.changes ?? []) { change in
                VStack(alignment: .leading, spacing: 2) {
                    Text(WikiVibeAgent(rawValue: change.agentId)?.title ?? change.agentId).font(.caption.bold())
                    Text(change.displayPath).font(.caption.monospaced()).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    private func failures(_ report: WikiVibeAgentReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array((report.failures ?? []).enumerated()), id: \.offset) { _, failure in
                Text("\(WikiVibeAgent(rawValue: failure.agentId)?.title ?? failure.agentId): \(failure.message)")
                    .foregroundStyle(.red).font(.caption)
            }
        }
    }
    private func resultView(_ report: WikiVibeAgentReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(report.failures?.isEmpty == false ? L10n.t("Some operations failed. Review changed files and errors below.") : L10n.t("Agent configuration files updated. Start a new agent session."))
                .font(.callout.weight(.medium))
            fileRows(report)
            failures(report)
        }
        .accessibilityIdentifier("keys.result")
    }
}
