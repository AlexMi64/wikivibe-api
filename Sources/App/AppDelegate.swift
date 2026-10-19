import AppKit
import Combine
import SwiftUI

/// Account and public gateway statistics only; no agent or credential discovery.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var fleet: NotchFleet?
    private var preferences: Preferences?
    private var accountWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    /// Owns the account session. Created on launch so the stored session is
    /// restored before the window first draws.
    private let auth = WikiVibeAuthCoordinator()
    private let performance = WikiVibePerformanceStore()

    static func drawn(_ snapshots: [ProviderSnapshot], weekly: Bool, paced: Bool)
    -> [ProviderSnapshot] {
        DailyPace.apply(to: WeeklyHeadline.apply(to: snapshots, enabled: weekly), enabled: paced)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        guard !Runtime.isUnderTest else { return }

        let preferences = Preferences()
        self.preferences = preferences
        let fleet = NotchFleet(scope: preferences.notchScope, edge: preferences.notchEdge)
        self.fleet = fleet
        fleet.onOpenSettings = { [weak self] in self?.toggleAccountWindow() }
        fleet.onTopUp = { [weak self] in self?.openTopUp() }
        // The notch has nothing to poll: this app reads the account, not usage.
        // Widget clicks toggle the account window instead of polling usage.
        fleet.onRefresh = { [weak self] in self?.toggleAccountWindow() }
        fleet.onRefreshProvider = { [weak self] _ in self?.toggleAccountWindow() }
        fleet.onReposition = { [weak preferences] offset in
            guard let preferences else { return }
            preferences.setOffset(offset, for: preferences.notchEdge)
        }
        fleet.onMoveToEdge = { [weak preferences] edge, offset in
            guard let preferences else { return }
            if let offset { preferences.setOffset(offset, for: edge) }
            preferences.notchEdge = edge
        }
        updateLocalizedSurface()
        applyAppearance()
        preferences.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                // @Published emits before mutation; apply the settled values.
                DispatchQueue.main.async { self?.applyAppearance() }
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: L10n.didChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateLocalizedSurface() }
            .store(in: &cancellables)
        // The notch row is the account's own state, so it is repainted when
        // sign-in, sign-out or a restore changes what the app knows.
        auth.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.updateLocalizedSurface() }
            }
            .store(in: &cancellables)
        performance.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.updateLocalizedSurface() }
            }
            .store(in: &cancellables)
        performance.start()
        fleet.show()
        // A stored session is picked up before the window can ask, so the
        // account row never briefly claims the user is signed out.
        Task { await auth.restore() }
        openSettings()
    }

    private func updateLocalizedSurface() {
        fleet?.signInItems = [(
            title: auth.account == nil ? L10n.t("Sign in to WikiVibe…") : L10n.t("WikiVibe account…"),
            action: { [weak self] in self?.openSettings() }
        )]
        fleet?.setSnapshots([accountSnapshot] + performance.snapshots)
        installMenu()
    }

    /// The account cell keeps balance separate from public model performance.
    private var accountSnapshot: ProviderSnapshot {
        let status: ProviderStatus
        let plan: String?
        var windows: [LimitWindow] = []
        switch auth.state {
        case .signedIn(let account):
            status = .ok
            plan = account.displayName
            if let wallet = auth.wallet {
                // A count row: the balance is an amount, not a fraction of a
                // limit, so it renders without a bar that would imply a ceiling
                // the server never stated.
                windows = [LimitWindow(
                    id: "balance",
                    label: L10n.t("Balance"),
                    usedText: wallet.regularText,
                    detail: wallet.bonusText.map { L10n.t("Bonus") + " " + $0 }
                )]
            }
        case .signingIn:
            status = .stale(since: Date())
            plan = L10n.t("Waiting for the browser…")
        case .signedOut:
            status = .needsAuth
            plan = nil
        case .failed(let message):
            status = .error(message)
            plan = nil
        }
        return ProviderSnapshot(
            id: "wikivibe", displayName: "WikiVibe", glyph: .wikivibe,
            fidelity: .official,
            status: status,
            windows: windows,
            plan: plan
        )
    }

    private func applyAppearance() {
        guard let fleet, let preferences else { return }
        fleet.apply(scope: preferences.notchScope)
        fleet.apply(edge: preferences.notchEdge)
        fleet.apply(preferences.notchVisibility)
        fleet.apply(scale: preferences.notchScale)
        fleet.apply(alongOffset: preferences.offset(for: preferences.notchEdge))
        fleet.apply(displayPreference: preferences.displayPreference)
        fleet.apply(surfaceStyle: preferences.notchSurfaceStyle)
        fleet.apply(accentColor: preferences.accentColor)
        fleet.apply(foldsForFullScreen: preferences.foldsForFullScreen)
    }

    private func installMenu() {
        let item = statusItem ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "w.circle", accessibilityDescription: "WikiVibe")
        item.button?.toolTip = "WikiVibe"
        let menu = NSMenu()
        let settings = NSMenuItem(title: "WikiVibe…", action: #selector(showAccount), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: L10n.t("Quit WikiVibe"), action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }

    private func toggleAccountWindow() {
        if let window = accountWindow, window.isVisible || window.isMiniaturized {
            window.performClose(nil)
        } else {
            openSettings()
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === accountWindow else { return }
        // Only the account window closes; the widget, session and polling stay alive.
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func openSettings() {
        guard let preferences else { return }
        if accountWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
            )
            window.title = "WikiVibe"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: WikiVibeAccountView(auth: auth, preferences: preferences, performance: performance))
            window.contentMinSize = NSSize(width: 420, height: 360)
            if !window.setFrameUsingName("WikiVibeAccountWindow") { window.center() }
            window.setFrameAutosaveName("WikiVibeAccountWindow")
            accountWindow = window
        }
        NSApp.setActivationPolicy(.regular)
        if accountWindow?.isMiniaturized == true { accountWindow?.deminiaturize(nil) }
        accountWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openTopUp() {
        guard !NSWorkspace.shared.open(WikiVibeAuthContract.topUp) else { return }
        let alert = NSAlert()
        alert.messageText = L10n.t("Could not open the system browser.")
        alert.informativeText = L10n.t("Open https://api.wikivibe.dev/purchase in your browser to top up your balance.")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        cancellables.removeAll()
        // Best effort: a sign-in still waiting owns a listening socket, and the
        // OS reclaims it when the process exits either way. Closing it here is
        // what lets the wait end cleanly if termination is not immediate.
        let listener = auth
        Task { await listener.cancelSignIn() }
        auth.stopWalletPolling()
        performance.stop()
        fleet?.stop()
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    }

    @objc private func showAccount() { openSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
}
