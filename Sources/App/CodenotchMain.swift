import SwiftUI

@main
struct WikiVibeMain: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(L10n.languageDefaultsKey) private var language = AppLanguage.system.rawValue

    var body: some Scene {
        // The notch is the UI; the panel is put up by the delegate. This scene
        // exists only because `App` needs one.
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button(L10n.t("Settings…", locale: AppLanguage(rawValue: language)?.locale ?? .current)) {
                        appDelegate.openSettings()
                    }
                    .keyboardShortcut(",", modifiers: .command)
                }
            }
    }
}
