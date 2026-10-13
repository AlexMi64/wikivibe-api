import AppKit
import SwiftUI

/// The account window: who is signed in, and the one action that changes it.
///
/// It shows a state the app actually verified, and nothing it did not. There is
/// no balance or spending here: this app is authorized to read the account, not
/// the wallet, and a row reading "no data" would be a claim about the account
/// rather than about the app's permissions. `Open WikiVibe` is a plain browser
/// navigation — it is not sign-in, and the copy says so.
struct WikiVibeAccountView: View {
    @ObservedObject var auth: WikiVibeAuthCoordinator
    @ObservedObject var preferences: Preferences
    @State private var browserOpenFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    statusRow
                    if let notice = auth.notice {
                        Text(notice)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    actions
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }
            if browserOpenFailed {
                Text(L10n.t("Could not open the system browser.")).foregroundStyle(.red)
            }
            Divider()
            appearanceControls
        }
        .id(preferences.language)
        .padding(24)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
        .task { await auth.restore() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image("glyph-wikivibe")
                .resizable().scaledToFit().frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text("WikiVibe").font(.title2.bold())
                Text(L10n.t("Account"))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch auth.state {
        case .signedIn(let account):
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.displayName).font(.headline)
                    if !account.email.isEmpty, account.email != account.displayName {
                        Text(account.email).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        case .signingIn:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L10n.t("Waiting for the browser to finish sign-in…"))
            }
        case .signedOut:
            Label(L10n.t("Not signed in"), systemImage: "person.crop.circle.badge.questionmark")
        case .failed(let message):
            Label {
                Text(message).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 10) {
            switch auth.state {
            case .signedIn:
                Button(L10n.t("Sign out")) {
                    Task { await auth.signOut() }
                }
                .disabled(auth.isBusy)
            case .signingIn:
                Button(L10n.t("Cancel")) {
                    Task { await auth.cancelSignIn() }
                }
            default:
                Button(L10n.t("Sign in")) {
                    Task { await auth.signIn() }
                }
                .disabled(auth.isBusy)
            }

            Button(L10n.t("Open WikiVibe")) {
                browserOpenFailed = !NSWorkspace.shared.open(WikiVibeAuthContract.issuer)
            }
            .accessibilityLabel(L10n.t("Open WikiVibe"))

            if auth.isBusy {
                ProgressView().controlSize(.small)
            }
        }
        Text(L10n.t("Signing in happens in your browser. This app never sees your password."))
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var appearanceControls: some View {
        VStack(alignment: .leading, spacing: 12) {
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
    }
}
