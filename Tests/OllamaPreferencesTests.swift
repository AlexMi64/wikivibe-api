import XCTest
@testable import Codenotch

@MainActor
final class OllamaPreferencesTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let suite = "OllamaPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    func testFreshAndUpstreamUsersKeepInventoryEnabledWithoutStartingRelay() {
        let store = defaults()
        let fresh = Preferences(defaults: store)
        XCTAssertFalse(fresh.isConnected("ollama-local"))
        XCTAssertFalse(fresh.ollamaMetricsEnabled)
        fresh.setConnected(false, for: "ollama-local")
        let next = Preferences(defaults: store)
        XCTAssertFalse(next.isConnected("ollama-local"))
        XCTAssertFalse(next.ollamaMetricsEnabled)
    }

    func testLegacyDisabledRuntimeAndHiddenModelsMigrateOnlyOnce() {
        let store = defaults()
        store.set(true, forKey: "introducedOllama")
        store.set(["cursor", "ollama", "ollama:model:qwen3"], forKey: "hiddenProviders")
        store.set(["ollama:model:qwen3", "codex", "ollama-local:model:qwen3", "ollama"], forKey: "providerOrder")
        store.set(["ollama", "claude"], forKey: "mutedAlertProviders")
        let preferences = Preferences(defaults: store)
        XCTAssertFalse(preferences.isConnected("cursor"))
        XCTAssertFalse(preferences.isConnected("ollama-local"))
        XCTAssertFalse(preferences.isConnected("ollama-local:model:qwen3"))
        XCTAssertEqual(preferences.disabledModels, ["ollama-local:model:qwen3"])
        XCTAssertEqual(preferences.providerOrder, ["ollama-local:model:qwen3", "codex", "ollama-local"])
        XCTAssertEqual(preferences.mutedAlertProviders, ["ollama-local", "claude"])
        XCTAssertFalse(preferences.ollamaMetricsEnabled)
        preferences.setConnected(true, for: "ollama-local")
        preferences.ollamaMetricsEnabled = false
        let next = Preferences(defaults: store)
        XCTAssertTrue(next.isConnected("ollama-local"))
        XCTAssertFalse(next.isConnected("ollama-local:model:qwen3"))
        XCTAssertFalse(next.ollamaMetricsEnabled)
    }

    func testLegacyEnabledRelayChoiceSurvivesAndCanonicalDisconnectionWins() {
        let store = defaults()
        store.set(true, forKey: "introducedOllama")
        XCTAssertTrue(Preferences(defaults: store).ollamaMetricsEnabled)
        store.set(["ollama-local"], forKey: "hiddenProviders")
        XCTAssertFalse(Preferences(defaults: store).ollamaMetricsEnabled)
    }

    func testUnrelatedOllamaIDIsNotRenamedWithoutLegacySentinel() {
        let store = defaults()
        store.set(["ollama"], forKey: "hiddenProviders")
        store.set(["ollama", "codex"], forKey: "providerOrder")
        let preferences = Preferences(defaults: store)
        XCTAssertFalse(preferences.isConnected("ollama"))
        XCTAssertEqual(preferences.providerOrder, ["ollama", "codex"])
        XCTAssertTrue(preferences.isConnected("ollama-local"))
    }
}
