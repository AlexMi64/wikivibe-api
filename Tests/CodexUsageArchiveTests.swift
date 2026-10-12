import XCTest
@testable import Codenotch

final class CodexUsageArchiveTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let name = "CodexUsageArchiveTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func snapshot(id: String = "codex",
                          windows: [LimitWindow]) -> ProviderSnapshot {
        ProviderSnapshot(
            id: id, displayName: "Codex", glyph: .openai,
            fidelity: .official, status: .ok,
            windows: windows
        )
    }

    private func roundTrip(_ snapshot: ProviderSnapshot,
                           defaults: UserDefaults? = nil) -> ProviderSnapshot? {
        let defaults = defaults ?? makeDefaults()
        UsageArchive(defaults: defaults).save([snapshot.id: (snapshot, Date())])
        return UsageArchive(defaults: defaults).load()[snapshot.id]?.snapshot
    }

    /// Spark is a live quota, not leftover rollout data. Reloading it after
    /// a relaunch is the archive's job.
    func testAnArchivedSparkWindowSurvivesRelaunch() {
        let restored = roundTrip(snapshot(windows: [
            LimitWindow(id: "primary", label: "5h limit", usedFraction: 0.2),
            LimitWindow(id: "spark", label: "Spark", usedFraction: 0.5)
        ]))
        XCTAssertEqual(restored?.windows.map(\.id), ["primary", "spark"])
        XCTAssertEqual(restored?.windows.last?.usedFraction, 0.5)
    }

    /// Old rollout quota ids are gone from the live provider. Restoring them
    /// would show numbers the UI no longer has a home for.
    func testAnArchivedRolloutQuotaIsSkipped() {
        XCTAssertNil(roundTrip(snapshot(windows: [
            LimitWindow(id: "rollout-foo", label: "Rollout", usedFraction: 0.9)
        ])))
    }

    /// A leftover rollout quota must not take a live Spark reading with it.
    func testASparkWindowSurvivesBesideAStrippedRolloutQuota() {
        let restored = roundTrip(snapshot(windows: [
            LimitWindow(id: "spark", label: "Spark", usedFraction: 0.5),
            LimitWindow(id: "rollout-foo", label: "Rollout", usedFraction: 0.9)
        ]))
        XCTAssertEqual(restored?.windows.map(\.id), ["spark"])
        XCTAssertEqual(restored?.windows.first?.usedFraction, 0.5)
    }

    func testLiveWindowsOnAnExtraProfileSurviveAndUnknownOnesDoNot() {
        let work = "codex-work"
        let spark = roundTrip(snapshot(id: work, windows: [
            LimitWindow(id: "spark-secondary", label: "Spark weekly", usedFraction: 0.1),
            LimitWindow(id: "code-review", label: "Code review", usedFraction: 0.3),
            LimitWindow(id: "code-review-secondary", label: "Code review weekly",
                        usedFraction: 0.4)
        ]))
        XCTAssertEqual(spark?.windows.map(\.id),
                       ["spark-secondary", "code-review", "code-review-secondary"])

        let mixed = roundTrip(snapshot(id: work, windows: [
            LimitWindow(id: "primary", label: "5h limit", usedFraction: 0.2),
            LimitWindow(id: "rollout-foo", label: "Rollout", usedFraction: 0.9)
        ]))
        XCTAssertEqual(mixed?.windows.map(\.id), ["primary"])
        XCTAssertEqual(mixed?.windows.first?.usedFraction, 0.2)

        XCTAssertNil(roundTrip(snapshot(id: work, windows: [
            LimitWindow(id: "rollout-foo", label: "Rollout", usedFraction: 0.9)
        ])))
    }

    /// The Codex filter is keyed on the provider id. A Claude session window
    /// must not be mistaken for leftover rollout data.
    func testANonCodexReadingIsLeftAlone() {
        let restored = roundTrip(snapshot(id: "claude", windows: [
            LimitWindow(id: "session", label: "Current session", usedFraction: 0.4)
        ]))
        XCTAssertEqual(restored?.windows.map(\.id), ["session"])
    }
}
