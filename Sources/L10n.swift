import Foundation

/// Visible copy. English source strings are the keys; `Localizable.xcstrings`
/// supplies every other language.
///
/// Looked up against this module's bundle, not `Bundle.main`, so unit tests
/// still find the catalog when the test host is the test bundle.
enum L10n {
    private final class Token {}

    static var bundle: Bundle { Bundle(for: Token.self) }

    /// Posted after `apply` so windows can rebuild copy. A notification
    /// rather than an observable object because `t` is called off the main
    /// actor from providers.
    static let didChange = Notification.Name("L10nDidChange")

    /// Persistence key for the in-app override. Not `AppleLanguages` — that
    /// would rewrite AppKit chrome too.
    static let languageDefaultsKey = "appLanguage"

    /// Where the override is kept. Injectable because the unit tests run
    /// inside the app as their host, so `.standard` here is the *shipping
    /// app's* preferences: without this, choosing 简体中文 in Settings would
    /// turn every copy assertion in the suite Chinese, and a test that stored
    /// a language would leave it behind in the real app.
    static var defaults: UserDefaults = .standard

    /// Tests set this to force a locale; nil means production rules.
    static var testLocale: Locale?

    static var locale: Locale {
        if let testLocale { return testLocale }

        let stored = defaults.string(forKey: languageDefaultsKey)
        let isTest = NSClassFromString("XCTestCase") != nil

        // Under XCTest the host *is* the app, so the production store here is
        // the preferences of the installed copy of Codenotch. Choosing 简体中文
        // in Settings would otherwise decide what a hundred copy assertions
        // compare against — which it did, twice, mid-session. A test that
        // means to exercise the override injects its own store and is
        // answered by the rules below.
        if isTest, defaults == .standard { return Locale(identifier: "en") }

        // Existing assertions stay English on a Chinese Mac. A stored
        // override still wins so a test can pin zh-Hans without testLocale.
        if isTest, stored == nil || stored == AppLanguage.system.rawValue {
            return Locale(identifier: "en")
        }

        if let stored,
           let language = AppLanguage(rawValue: stored),
           let locale = language.locale {
            return locale
        }
        return .current
    }

    /// One bundle per language, resolved once.
    ///
    /// `t` is called from view bodies that the notch's 0.3s cursor poll
    /// repaints, so its cost is paid a few hundred times a second.
    private static let bundlesLock = NSLock()
    private static var bundles: [String: Bundle] = [:]

    /// The `.lproj` holding `locale`'s copy, or nil when the catalog has none.
    private static func bundle(for locale: Locale) -> Bundle? {
        bundlesLock.lock()
        defer { bundlesLock.unlock() }
        if let hit = bundles[locale.identifier] { return hit }
        // Matches the way the identifier is spelled to the way the catalog
        // spells it: en_US to en, pt_BR to pt-BR.
        guard let name = Bundle.preferredLocalizations(
                  from: bundle.localizations, forPreferences: [locale.identifier]
              ).first,
              let url = bundle.url(forResource: name, withExtension: "lproj"),
              let resolved = Bundle(url: url)
        else { return nil }
        bundles[locale.identifier] = resolved
        return resolved
    }

    static func t(_ key: String.LocalizationValue, locale: Locale = locale) -> String {
        // `String(localized:locale:)` only formats interpolated numbers; it
        // still looks the string up in the bundle's preferred language. So the
        // locale has to be carried in by *which bundle* is asked — a bundle
        // holding that language alone — which is what the XCTest pin needs on
        // a Chinese Mac.
        //
        // Not `LocalizedStringResource(bundle: .atURL(…))`, which does carry a
        // locale but re-resolves the bundle on every lookup and so misses
        // CFBundle's string-table cache: each call re-read and re-parsed the
        // whole 128KB `Localizable.strings`. That measured 0.78ms a call
        // against 0.001ms here, and left 57% of the main thread inside
        // `_CFBundleCopyLocalizedStringForLocalizations` on an idle app.
        guard let languageBundle = bundle(for: locale) else {
            return String(localized: LocalizedStringResource(
                key, locale: locale, bundle: .atURL(bundle.bundleURL)
            ))
        }
        return String(localized: key, bundle: languageBundle, locale: locale)
    }

    static func apply(_ language: AppLanguage) {
        // Absence, not the string "system": the XCTest English pin treats a
        // missing key as follow-the-Mac.
        if language == .system {
            defaults.removeObject(forKey: languageDefaultsKey)
        } else {
            defaults.set(language.rawValue, forKey: languageDefaultsKey)
        }
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}
