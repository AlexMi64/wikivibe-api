import AppKit
import SwiftUI

/// A prerequisite state, not a fake signed-in account or backend connector.
struct WikiVibeAccountView: View {
    @ObservedObject var preferences: Preferences
    @State private var browserOpenFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image("glyph-wikivibe")
                    .resizable().scaledToFit().frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text("WikiVibe").font(.title2.bold())
                    Text(L10n.t("Account integration unavailable")).foregroundStyle(.secondary)
                }
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Label(L10n.t("Desktop client and callback required"), systemImage: "exclamationmark.circle")
                        .font(.headline)
                    Text(L10n.t("Desktop client registration and an allowed callback must be confirmed. This app stores no account session and displays no unverified amounts."))
                    Button(L10n.t("Open authentication website")) {
                        let opened = NSWorkspace.shared.open(URL(string: "https://auth.wikivibe.dev/")!)
                        browserOpenFailed = !opened
                    }
                    .accessibilityLabel(L10n.t("Open authentication website"))
                    Button(L10n.t("Top up on website")) {
                        let opened = NSWorkspace.shared.open(URL(string: "https://api.wikivibe.dev/purchase")!)
                        browserOpenFailed = !opened
                    }
                    .accessibilityLabel(L10n.t("Top up on website"))
                    Text(L10n.t("Opening the website does not sign in to this app."))
                        .font(.caption).foregroundStyle(.secondary)
                    if browserOpenFailed {
                        Text(L10n.t("Could not open the system browser.")).foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }
            HStack {
                Text(L10n.t("Balance")).foregroundStyle(.secondary)
                Spacer()
                Text(L10n.t("No confirmed data"))
            }
            HStack {
                Text(L10n.t("Spending and period")).foregroundStyle(.secondary)
                Spacer()
                Text(L10n.t("No confirmed data"))
            }
            Divider()
            Picker(L10n.t("Language"), selection: $preferences.language) {
                ForEach([AppLanguage.system, .english, .russian, .simplifiedChinese]) { language in
                    Text(language.title).tag(language)
                }
            }
            Text(L10n.t("Widget")).font(.headline)
            Picker(L10n.t("Screen edge"), selection: $preferences.notchEdge) {
                ForEach(NotchEdge.allCases) { edge in Text(edge.title).tag(edge) }
            }
            Picker(L10n.t("Size"), selection: $preferences.notchSize) {
                ForEach(NotchSize.allCases) { size in Text(size.title).tag(size) }
            }
            Picker(L10n.t("Visibility"), selection: $preferences.notchVisibility) {
                ForEach(NotchVisibility.allCases) { visibility in Text(visibility.title).tag(visibility) }
            }
        }
        .id(preferences.language)
        .padding(24)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
    }
}
