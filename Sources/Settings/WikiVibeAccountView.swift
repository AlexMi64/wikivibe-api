import AppKit
import SwiftUI

/// The account window: who is signed in, what the account holds, and the one
/// action that changes it.
///
/// Every number here came from the server and says when it was read. Nothing is
/// derived from local logs, and nothing is shown as zero because it was missing:
/// a balance the app could not read is reported as unreadable, which is a
/// different fact from "you have nothing".
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
            if case .signedIn = auth.state {
                walletSection
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
        .task {
            await auth.restore()
            // The window is where the number is read, so opening it is a good
            // moment to make sure it is current — and to start the poll if the
            // app launched before a session existed.
            auth.setWalletVisible(true)
            await auth.loadWallet()
            auth.startWalletPolling()
        }
        .onDisappear { auth.setWalletVisible(false) }
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

    /// Money the server reported, or why it is missing.
    @ViewBuilder
    private var walletSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L10n.t("Balance")).font(.headline)
                    Spacer()
                    if auth.isLoadingWallet {
                        ProgressView().controlSize(.small)
                    } else if let refresh = auth.wallet {
                        Text(refresh.currencyName)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                if let wallet = auth.wallet {
                    amountRow(L10n.t("Regular"), wallet.regularText, emphasized: true)
                    if let bonus = wallet.bonusText {
                        amountRow(L10n.t("Bonus"), bonus)
                    }
                    if let frozen = wallet.frozenText {
                        amountRow(L10n.t("On hold"), frozen)
                    }
                } else if let error = auth.walletError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(L10n.t("Reading the balance…"))
                        .font(.callout).foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Button(L10n.t("Refresh")) {
                        Task { await auth.loadWallet() }
                    }
                    .disabled(auth.isLoadingWallet)
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    private func amountRow(_ title: String, _ value: String, emphasized: Bool = false) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(emphasized ? .title3.bold() : .body)
                .monospacedDigit()
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

            // Named for what it does. The previous label, "Open WikiVibe",
            // promised a signed-in destination and delivered the site's login
            // page — the site has its own browser session, which this app's
            // session does not create. The hint below says so.
            Button(L10n.t("Open the website")) {
                browserOpenFailed = !NSWorkspace.shared.open(WikiVibeAuthContract.panel)
            }
            .accessibilityLabel(L10n.t("Open the website"))

            if auth.isBusy {
                ProgressView().controlSize(.small)
            }
        }
        Text(L10n.t("Signing in happens in your browser. This app never sees your password."))
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        Text(L10n.t("The website keeps its own sign-in. If it asks for a password, you have not signed in there in this browser yet."))
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
