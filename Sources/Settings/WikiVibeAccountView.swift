import AppKit
import SwiftUI

private enum AccountSection: Hashable, Identifiable {
    case card(AccountWindowLayout.Card)
    case models

    var id: Self { self }
    var title: String {
        switch self {
        case .card(let card): return card.title
        case .models: return L10n.t("Model context windows")
        }
    }
    var symbol: String {
        switch self {
        case .card(let card): return card.symbol
        case .models: return "square.stack.3d.up"
        }
    }
    var accessibilityID: String {
        switch self {
        case .card(let card): return "account.card.\(card.rawValue)"
        case .models: return "account.card.models"
        }
    }
}

private enum AccountDashboardStyle {
    static let cardRadius: CGFloat = 14
    static let darkPage = Color(red: 0.018, green: 0.025, blue: 0.040)
    static let darkCard = Color(red: 0.035, green: 0.052, blue: 0.078)
    static let cardFill = Color.white.opacity(0.055)
    static let cardEdge = Color.white.opacity(0.10)
    static let cardHighlight = Color.white.opacity(0.06)
    static let pageGlow = Color(red: 0.02, green: 0.32, blue: 0.95).opacity(0.16)

    static func pageBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? darkPage : Color(nsColor: .windowBackgroundColor)
    }

    static func cardFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? darkCard : cardFill
    }

    static func accent(for section: AccountSection) -> Color {
        switch section {
        case .card(.account): return .green
        case .card(.balance): return .blue
        case .card(.appearance): return .orange
        case .card(.apiKeys): return .purple
        case .models: return .cyan
        }
    }
}

struct WikiVibeAccountView: View {
    @ObservedObject var auth: WikiVibeAuthCoordinator
    @ObservedObject var preferences: Preferences
    @ObservedObject var performance: WikiVibePerformanceStore
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var keys = WikiVibeKeysController()
    @State private var browserOpenFailed = false
    @State private var isCustomizing = false

    private var layout: AccountWindowLayout { preferences.accountWindowLayout }
    private var sections: [AccountSection] {
        layout.visibleCards.flatMap { card in
            card == .apiKeys && !keys.models.isEmpty ? [.card(card), .models] : [.card(card)]
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let width = max(0, geometry.size.width - layout.density.padding * 2)
            let sections = self.sections
            let columns = layout.columnCount(availableWidth: width, sectionCount: sections.count)
            ScrollView {
                VStack(alignment: .leading, spacing: layout.density.spacing) {
                    header(compact: width < 500)
                    if layout.visibleCards.isEmpty {
                        Text(L10n.t("All cards are hidden. Use Customize to show them again."))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 160)
                    } else {
                        AccountCardLayout(columns: columns, spacing: layout.density.spacing) {
                            ForEach(sections) { section in cardView(section) }
                        }
                        .frame(width: width)
                    }
                }
                .id(preferences.language)
                .padding(layout.density.padding)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background {
                ZStack {
                    AccountDashboardStyle.pageBackground(for: colorScheme)
                    RadialGradient(colors: [AccountDashboardStyle.pageGlow, .clear],
                                   center: .topLeading, startRadius: 0, endRadius: 520)
                        .opacity(0.9)
                }
                .ignoresSafeArea()
            }
        }
        .frame(minWidth: 420, minHeight: 360)
        .task {
            await auth.restore()
            auth.setWalletVisible(true)
            await auth.loadWallet()
            auth.startWalletPolling()
        }
        .task(id: layout.isVisible(.apiKeys) ? auth.account?.id : nil) {
            keys.clear()
            if layout.isVisible(.apiKeys), auth.account != nil { await keys.load(auth: auth) }
        }
        .onDisappear {
            auth.setWalletVisible(false)
            keys.clear()
        }
    }

    private func header(compact: Bool) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(colors: [.blue.opacity(0.9), .purple.opacity(0.85)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                Image("glyph-wikivibe")
                    .resizable().scaledToFit().padding(7)
            }
            .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 2) {
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
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .controlSize(.regular)
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
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .accessibilityLabel(L10n.t("Reset window layout"))
            .help(L10n.t("Reset window layout"))
            .accessibilityIdentifier("layout.reset")
        }
        .padding(.bottom, 2)
    }

    private func cardView(_ section: AccountSection) -> some View {
        let accent = AccountDashboardStyle.accent(for: section)
        return VStack(alignment: .leading, spacing: layout.density.spacing) {
            Label(section.title, systemImage: section.symbol)
                .font(.headline)
                .foregroundStyle(.primary)
                .symbolRenderingMode(.hierarchical)
                .tint(accent)
            Divider()
                .overlay(accent.opacity(0.20))
            switch section {
            case .card(.account): accountSection
            case .card(.balance): walletSection
            case .card(.appearance): appearanceControls
            case .card(.apiKeys): WikiVibeAPIKeysView(auth: auth, model: keys)
            case .models: WikiVibeModelContextsView(model: keys)
            }
        }
        .padding(layout.density.padding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: AccountDashboardStyle.cardRadius, style: .continuous)
                .fill(AccountDashboardStyle.cardFill(for: colorScheme))
                .overlay {
                    RoundedRectangle(cornerRadius: AccountDashboardStyle.cardRadius, style: .continuous)
                        .fill(LinearGradient(colors: [AccountDashboardStyle.cardHighlight, .clear],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                }
        }
        .overlay(alignment: .topLeading) {
            Capsule(style: .continuous)
                .fill(accent.gradient)
                .frame(width: 46, height: 3)
                .padding(.leading, layout.density.padding)
        }
        .overlay {
            RoundedRectangle(cornerRadius: AccountDashboardStyle.cardRadius, style: .continuous)
                .strokeBorder(AccountDashboardStyle.cardEdge, lineWidth: 1)
        }
        .accessibilityIdentifier(section.accessibilityID)
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
                        .buttonStyle(.bordered)
                        .controlSize(.small)
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

    @ViewBuilder
    private var appearanceControls: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
            formRow(L10n.t("Language")) {
                AetherSelectionMenu(L10n.t("Language"), selection: $preferences.language,
                                    options: [.system, .english, .russian, .simplifiedChinese],
                                    accent: .blue, identifier: "account.language", title: \.title)
            }
            formRow(L10n.t("Screen edge")) {
                AetherSelectionMenu(L10n.t("Screen edge"), selection: $preferences.notchEdge,
                                    options: NotchEdge.allCases, accent: .blue,
                                    title: \.title)
            }
            formRow(L10n.t("Size")) {
                AetherSelectionMenu(L10n.t("Size"), selection: $preferences.notchSize,
                                    options: NotchSize.allCases, accent: .blue,
                                    title: \.title)
            }
            formRow(L10n.t("Visibility")) {
                AetherSelectionMenu(L10n.t("Visibility"), selection: $preferences.notchVisibility,
                                    options: NotchVisibility.allCases, accent: .blue,
                                    title: \.title)
            }
        }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.t("Model speed in hover card")).font(.subheadline.bold())
                Spacer()
                Button(L10n.t("Refresh")) { Task { await performance.refresh() } }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(performance.isRefreshing)
            }
            if performance.catalogFailed {
                Text(L10n.t("Could not load server performance.")).foregroundStyle(.secondary)
            } else if performance.models.isEmpty {
                Text(L10n.t("Loading server performance…")).foregroundStyle(.secondary)
            }
            ForEach(performance.models) { model in
                HStack {
                    Toggle(model.displayName, isOn: Binding(
                        get: { performance.selectedIDs.contains(model.id) },
                        set: {
                            performance.setSelected(model.id, enabled: $0)
                            Task { await performance.refresh() }
                        }
                    ))
                    .toggleStyle(AetherCheckboxStyle())
                    .accessibilityIdentifier("performance.model." + model.id)
                    Spacer(minLength: 8)
                    TimelineView(.periodic(from: .now, by: 60)) { _ in
                        HStack(spacing: 4) {
                            Text(performance.isStale(model.id) ? "— tok/s" : performance.speedText(for: model.id))
                                .monospacedDigit().foregroundStyle(.secondary)
                            if performance.isStale(model.id) {
                                Image(systemName: "exclamationmark.triangle")
                                    .help(L10n.t("Reading is stale; check its date."))
                            }
                        }
                    }
                }
            }
        }
        .padding(.top, 12)
    }

    private func formRow<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
                .gridColumnAlignment(.leading)
            control().labelsHidden()
                .aetherControlSurface()
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
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .controlSize(.small)
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                formRow(L10n.t("Card layout")) {
                    AetherSelectionMenu(L10n.t("Card layout"), selection: $preferences.accountWindowLayout.arrangement,
                                        options: AccountWindowLayout.Arrangement.allCases, accent: .blue,
                                        identifier: "layout.arrangement", title: \.title)
                }
                formRow(L10n.t("Card spacing")) {
                    AetherSelectionMenu(L10n.t("Card spacing"), selection: $preferences.accountWindowLayout.density,
                                        options: AccountWindowLayout.Density.allCases, accent: .blue,
                                        identifier: "layout.density", title: \.title)
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
                    .toggleStyle(AetherCheckboxStyle())
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
