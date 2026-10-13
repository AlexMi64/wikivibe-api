import AppKit
import Combine
import SwiftUI

/// WikiVibe owns its account session. Upstream credential discovery, agent
/// monitoring, local cost indexing, phone serving and update feeds are not
/// started by this product.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var fleet: NotchFleet?
    private var preferences: Preferences?
    private var accountWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

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
        fleet.onOpenSettings = { [weak self] in self?.openSettings() }
        // Account API routes exist, but no desktop session can be established
        // without a confirmed public client and callback. Explain rather than poll.
        fleet.onRefresh = { [weak self] in self?.openSettings() }
        fleet.onRefreshProvider = { [weak self] _ in self?.openSettings() }
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
        fleet.show()
        openSettings()
    }

    private func updateLocalizedSurface() {
        fleet?.signInItems = [(title: L10n.t("WikiVibe — integration status…"), action: { [weak self] in
            self?.openSettings()
        })]
        fleet?.setSnapshots([ProviderSnapshot(
            id: "wikivibe", displayName: "WikiVibe", glyph: .wikivibe,
            fidelity: .official,
            status: .unsupported(L10n.t("Sign-in and balance unavailable: desktop client and callback must be confirmed.")),
            windows: []
        )])
        installMenu()
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

    func openSettings() {
        guard let preferences else { return }
        if accountWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 550),
                styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false
            )
            window.title = "WikiVibe"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: WikiVibeAccountView(preferences: preferences))
            window.center()
            accountWindow = window
        }
        accountWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        cancellables.removeAll()
        fleet?.stop()
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    }

    @objc private func showAccount() { openSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
}
