import SwiftUI

struct WikiVibeModelContextRow: View {
    let item: WikiVibeModel
    @Binding var contextWindow: Int?
    @State private var showingDetails = false
    @Environment(\.colorScheme) private var colorScheme

    private var retired: Bool { item.id == "gemini-3.1-flash-lite-preview" }
    private var options: [Int] {
        [-1] + Set(WikiVibeKeysController.contextWindowOptions.compactMap { $0 })
            .union(contextWindow.map { [$0] } ?? []).sorted()
    }

    var body: some View {
        HStack(spacing: 8) {
            Toggle(item.displayName, isOn: Binding(
                get: { contextWindow != nil },
                set: { enabled in contextWindow = enabled ? 1_000_000 : nil }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)
            .fixedSize()
            .accessibilityLabel(L10n.t("Override context window") + ": " + item.displayName)
            .accessibilityIdentifier("keys.context.enabled.\(item.id)")

            Text(item.displayName)
                .font(.caption.monospaced())
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(item.id)

            AetherSelectionMenu(L10n.t("Context window"), selection: Binding(
                get: { contextWindow ?? -1 },
                set: { contextWindow = $0 > 0 ? $0 : nil }
            ), options: options, accent: .cyan, identifier: "keys.context.\(item.id)", title: {
                WikiVibeKeysController.contextLabel($0 > 0 ? $0 : nil)
            })
            .frame(width: 136)

            Button { showingDetails.toggle() } label: {
                Image(systemName: retired ? "exclamationmark.triangle" : "info.circle")
                    .foregroundStyle(retired ? Color.orange : Color.secondary)
                    .frame(width: 22, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("Model details and custom context"))
            .accessibilityIdentifier("keys.context.details.\(item.id)")
            .popover(isPresented: $showingDetails) { details }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(AccountControlPalette.surface(colorScheme), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("keys.context.row.\(item.id)")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.id).font(.caption.monospaced()).textSelection(.enabled)
            if let documented = item.documentedContextWindow {
                Text(item.id.hasPrefix("gemini-")
                    ? L10n.t("Documented input limit: \(String(documented)) tokens")
                    : L10n.t("Documented provider limit: \(WikiVibeKeysController.contextLabel(documented))"))
            } else {
                Text(L10n.t("No exact official limit found for this catalog ID."))
            }
            if let url = item.documentationURL { Link(L10n.t("Source"), destination: url) }
            if retired {
                Text(L10n.t("Google has shut down this preview. Gateway availability is not verified."))
                    .foregroundStyle(.orange)
            }
            if let limit = contextWindow {
                Text(L10n.t("Custom tokens")).font(.subheadline)
                TextField(L10n.t("Custom tokens"), value: Binding(
                    get: { contextWindow ?? limit },
                    set: { if $0 > 0 && $0 <= 9_007_199_254_740_991 { contextWindow = $0 } }
                ), format: .number.grouping(.never))
                .textFieldStyle(.plain)
                .aetherControlSurface(accent: .cyan)
                .accessibilityIdentifier("keys.context.custom.\(item.id)")
            }
        }
        .font(.caption)
        .padding(16)
        .frame(width: 320, alignment: .leading)
        .background(AccountControlPalette.panel(colorScheme))
        .presentationBackground(AccountControlPalette.panel(colorScheme))
    }
}
