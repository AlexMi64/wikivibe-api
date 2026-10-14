import AppKit
import SwiftUI

/// Account, money and widget controls share a responsive card grid. Layout
/// preferences are presentation only and never change the authentication flow.
struct WikiVibeAccountView: View {
    @ObservedObject var auth: WikiVibeAuthCoordinator
    @ObservedObject var preferences: Preferences
    @State private var browserOpenFailed = false
    @State private var isCustomizing = false

    private var layout: AccountWindowLayout { preferences.accountWindowLayout }

    var body: some View {
        GeometryReader { geometry in
            let width = max(0, geometry.size.width - layout.density.padding * 2)
            let columns = layout.columnCount(availableWidth: width)
            ScrollView {
                VStack(alignment: .leading, spacing: layout.density.spacing) {
                    header(compact: width < 500)
                    if layout.visibleCards.isEmpty {
                        Text(L10n.t("All cards are hidden. Use Customize to show them again."))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 160)
                    } else {
                        cardGrid(width: width, columns: columns)
                    }
                }
                .id(preferences.language)
                .padding(layout.density.padding)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 420, minHeight: 360)
        .task {
            await auth.restore()
            auth.setWalletVisible(true)
            await auth.loadWallet()
            auth.startWalletPolling()
        }
        .onDisappear { auth.setWalletVisible(false) }
    }

    private func header(compact: Bool) -> some View {
        HStack(spacing: 12) {
            Image("glyph-wikivibe")
                .resizable().scaledToFit().frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text("WikiVibe").font(.title2.bold())
                Text(L10n.t("Account")).font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button {
                isCustomizing.toggle()
            } label: {
                if compact {
                    Image(systemName: "slider.horizontal.3")
                } else {
                    Label(L10n.t("Customize window"), systemImage: "slider.horizontal.3")
                }
            }
            .accessibilityLabel(L10n.t("Customize window"))
            .help(L10n.t("Customize window"))
            .accessibilityIdentifier("layout.customize")
            .popover(isPresented: $isCustomizing, arrowEdge: .bottom) {
                layoutEditor
            }
            Button {
                preferences.accountWindowLayout = AccountWindowLayout()
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .accessibilityLabel(L10n.t("Reset window layout"))
            .help(L10n.t("Reset window layout"))
            .accessibilityIdentifier("layout.reset")
        }
    }

    private func cardGrid(width: CGFloat, columns: Int) -> some View {
        let cards = layout.visibleCards
        let rows = stride(from: 0, to: cards.count, by: columns).map {
            Array(cards[$0..<min($0 + columns, cards.count)])
        }
        let cellWidth = max(0, (width - CGFloat(columns - 1) * layout.density.spacing) / CGFloat(columns))
        return Grid(alignment: .topLeading, horizontalSpacing: layout.density.spacing,
                    verticalSpacing: layout.density.spacing) {
            ForEach(rows.indices, id: \.self) { row in
                GridRow(alignment: .top) {
                    ForEach(rows[row]) { card in
                        cardView(card)
                            .frame(width: rows[row].count == 1 ? width : cellWidth, alignment: .topLeading)
                            .gridCellColumns(rows[row].count == 1 ? columns : 1)
                    }
                }
            }
        }
    }

    private func cardView(_ card: AccountWindowLayout.Card) -> some View {
        VStack(alignment: .leading, spacing: layout.density.spacing) {
            Label(card.title, systemImage: card.symbol)
                .font(.headline)
            Divider()
            switch card {
            case .account: accountSection
            case .balance: walletSection
            case .appearance: appearanceControls
            case .apiKeys: WikiVibeAPIKeysView(auth: auth).id(auth.account?.id)
            }
        }
        .padding(layout.density.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14).strokeBorder(.quaternary, lineWidth: 1)
        }
        .accessibilityIdentifier("account.card.\(card.rawValue)")
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusRow
            if let notice = auth.notice {
                Text(notice).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actions
            if browserOpenFailed {
                Text(L10n.t("Could not open the system browser."))
                    .font(.callout).foregroundStyle(.red)
            }
            DisclosureGroup(L10n.t("About signing in")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.t("Signing in happens in your browser. This app never sees your password."))
                    Text(L10n.t("The website keeps its own sign-in. If it asks for a password, you have not signed in there in this browser yet."))
                }
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            }
            .font(.callout)
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch auth.state {
        case .signedIn(let account):
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 3) {
                    Text(account.displayName).font(.headline)
                    if !account.email.isEmpty, account.email != account.displayName {
                        Text(account.email).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
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
    private var walletSection: some View {
        if case .signedIn = auth.state {
            VStack(alignment: .leading, spacing: 12) {
                if let wallet = auth.wallet {
                    Grid(horizontalSpacing: 16, verticalSpacing: 10) {
                        amountRow(L10n.t("Regular"), wallet.regularText, emphasized: true)
                        if let bonus = wallet.bonusText { amountRow(L10n.t("Bonus"), bonus) }
                        if let frozen = wallet.frozenText { amountRow(L10n.t("On hold"), frozen) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if let error = auth.walletError {
                    Text(error).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(L10n.t("Reading the balance…")).foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Button(L10n.t("Refresh")) { Task { await auth.loadWallet() } }
                        .disabled(auth.isLoadingWallet)
                    if auth.isLoadingWallet {
                        ProgressView().controlSize(.small)
                    }
                    Spacer(minLength: 0)
                    if let wallet = auth.wallet {
                        Text(wallet.currencyName).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            Text(L10n.t("Sign in to WikiVibe to show your account"))
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func amountRow(_ title: String, _ value: String, emphasized: Bool = false) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary).gridColumnAlignment(.leading)
            Text(value)
                .font(emphasized ? .title2.bold() : .body)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .trailing)
                .gridColumnAlignment(.trailing)
        }
    }

    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { sessionButton; websiteButton }
            VStack(alignment: .leading, spacing: 8) { sessionButton; websiteButton }
        }
        .controlSize(.regular)
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private var sessionButton: some View {
        switch auth.state {
        case .signedIn:
            Button(L10n.t("Sign out")) { Task { await auth.signOut() } }.disabled(auth.isBusy)
        case .signingIn:
            Button(L10n.t("Cancel")) { Task { await auth.cancelSignIn() } }
        default:
            Button(L10n.t("Sign in")) { Task { await auth.signIn() } }.disabled(auth.isBusy)
        }
    }

    private var websiteButton: some View {
        Button(L10n.t("Open the website")) {
            browserOpenFailed = !NSWorkspace.shared.open(WikiVibeAuthContract.panel)
        }
        .accessibilityLabel(L10n.t("Open the website"))
    }

    private var appearanceControls: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
            formRow(L10n.t("Language")) {
                Picker(L10n.t("Language"), selection: $preferences.language) {
                    ForEach([AppLanguage.system, .english, .russian, .simplifiedChinese]) { language in
                        Text(language.title).tag(language)
                    }
                }
                .accessibilityIdentifier("account.language")
            }
            formRow(L10n.t("Screen edge")) {
                Picker(L10n.t("Screen edge"), selection: $preferences.notchEdge) {
                    ForEach(NotchEdge.allCases) { edge in Text(edge.title).tag(edge) }
                }
            }
            formRow(L10n.t("Size")) {
                Picker(L10n.t("Size"), selection: $preferences.notchSize) {
                    ForEach(NotchSize.allCases) { size in Text(size.title).tag(size) }
                }
            }
            formRow(L10n.t("Visibility")) {
                Picker(L10n.t("Visibility"), selection: $preferences.notchVisibility) {
                    ForEach(NotchVisibility.allCases) { visibility in Text(visibility.title).tag(visibility) }
                }
            }
        }
    }

    private func formRow<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
                .gridColumnAlignment(.leading)
            control().labelsHidden()
                .frame(maxWidth: .infinity)
                .gridColumnAlignment(.trailing)
        }
    }

    private var layoutEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L10n.t("Customize window")).font(.headline)
                Spacer()
                Button(L10n.t("Done")) { isCustomizing = false }
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                formRow(L10n.t("Card layout")) {
                    Picker(L10n.t("Card layout"), selection: $preferences.accountWindowLayout.arrangement) {
                        ForEach(AccountWindowLayout.Arrangement.allCases) { Text($0.title).tag($0) }
                    }
                    .accessibilityIdentifier("layout.arrangement")
                }
                formRow(L10n.t("Card spacing")) {
                    Picker(L10n.t("Card spacing"), selection: $preferences.accountWindowLayout.density) {
                        ForEach(AccountWindowLayout.Density.allCases) { Text($0.title).tag($0) }
                    }
                    .accessibilityIdentifier("layout.density")
                }
            }
            Text(L10n.t("Widen the window for more columns. Narrow windows stack cards automatically."))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            Text(L10n.t("Card order and visibility")).font(.subheadline.bold())
            ForEach(Array(layout.orderedCards.enumerated()), id: \.element.id) { index, card in
                HStack(spacing: 8) {
                    Toggle(card.title, isOn: Binding(
                        get: { layout.isVisible(card) },
                        set: { preferences.accountWindowLayout.setVisible($0, for: card) }
                    ))
                    .toggleStyle(.checkbox)
                    .accessibilityIdentifier("layout.visible.\(card.rawValue)")
                    Spacer(minLength: 8)
                    Button {
                        preferences.accountWindowLayout.move(card, by: -1)
                    } label: { Image(systemName: "arrow.up") }
                    .disabled(index == 0)
                    .accessibilityLabel(L10n.t("Move \(card.title) up"))
                    .accessibilityIdentifier("layout.move.\(card.rawValue).up")
                    Button {
                        preferences.accountWindowLayout.move(card, by: 1)
                    } label: { Image(systemName: "arrow.down") }
                    .disabled(index == layout.orderedCards.count - 1)
                    .accessibilityLabel(L10n.t("Move \(card.title) down"))
                    .accessibilityIdentifier("layout.move.\(card.rawValue).down")
                }
            }
        }
        .padding(20)
        .frame(width: 400)
        .id(preferences.language)
    }
}
