import XCTest
@testable import Codenotch

@MainActor
final class WikiVibePerformanceTests: XCTestCase {
    func testMissingSamplesAreNotMeasuredZeroAndMeasuredZeroIsValid() {
        let empty = WikiVibePerformanceReading.Summary(metricSampleCount: 0, avgTokensPerSec: 0, avgTtftMs: 0)
        XCTAssertNil(empty.tokensPerSecond)
        XCTAssertNil(empty.firstTokenSeconds)
        let missing = WikiVibePerformanceReading.Summary(metricSampleCount: 2, avgTokensPerSec: nil, avgTtftMs: nil)
        XCTAssertNil(missing.tokensPerSecond)
        let measured = WikiVibePerformanceReading.Summary(metricSampleCount: 2, avgTokensPerSec: 0, avgTtftMs: 1250)
        XCTAssertEqual(measured.tokensPerSecond, 0)
        XCTAssertEqual(measured.firstTokenSeconds, 1.25)
        XCTAssertNil(WikiVibePerformanceReading.Summary(metricSampleCount: 1, avgTokensPerSec: -.infinity, avgTtftMs: -1).tokensPerSecond)
    }

    func testPartialFailureKeepsLastMeasurementStaleAndOtherModelsUpdate() async {
        let api = PerformanceFixture()
        let suite = "performance-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var clock = Date(timeIntervalSince1970: 10_000)
        let store = WikiVibePerformanceStore(api: api, defaults: defaults, now: { clock })
        await store.refresh()
        store.setSelected("second", enabled: true)
        await api.failFirst()
        clock.addTimeInterval(300)
        await store.refresh()
        let first = store.snapshots.first!
        XCTAssertEqual(first.headlineText, "20 tok/s")
        XCTAssertTrue(first.status.isStale)
        XCTAssertNil(first.ringFraction)
        XCTAssertEqual(store.snapshots.last?.headlineText, "40 tok/s")
        XCTAssertEqual(store.snapshots.last?.status, .ok)
        await api.failCatalog()
        clock.addTimeInterval(3600)
        await store.refresh()
        XCTAssertEqual(store.snapshots.count, 2)
        XCTAssertTrue(store.snapshots.allSatisfy { $0.status.isStale })
    }

    func testExplicitEmptySelectionSurvivesRefreshAndNewStore() async {
        let api = PerformanceFixture()
        let suite = "performance-selection-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WikiVibePerformanceStore(api: api, defaults: defaults)
        await store.refresh()
        for id in store.selectedIDs { store.setSelected(id, enabled: false) }
        await store.refresh()
        XCTAssertTrue(store.snapshots.isEmpty)
        let restored = WikiVibePerformanceStore(api: api, defaults: defaults)
        await restored.refresh()
        XCTAssertTrue(restored.snapshots.isEmpty)
    }

    func testEnvelopeErrorsAndWrongModelCannotBecomeMeasurements() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PerformanceProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); PerformanceProtocol.body = "" }
        let api = WikiVibePerformanceAPI(session: session)
        PerformanceProtocol.body = #"{"code":42,"data":[]}"#
        do { _ = try await api.models(); XCTFail("Nonzero envelope must fail") } catch {}
        PerformanceProtocol.body = #"{"code":0,"data":{"model":"foreign","hours":24,"coverage":{"start":"2026-10-18T00:00:00.123456789Z","end":"2026-10-19T00:00:00Z"},"summary":{"metric_sample_count":1,"avg_tokens_per_sec":90}}}"#
        do { _ = try await api.performance(modelID: "wanted"); XCTFail("A different model must not be displayed") } catch {}
        PerformanceProtocol.body = #"{"code":0,"data":{"model":"wanted","hours":24,"coverage":{"start":"2026-10-18T00:00:00Z","end":"2026-10-19T00:00:00Z"}}}"#
        let empty = try await api.performance(modelID: "wanted")
        XCTAssertNil(empty.summary)
        PerformanceProtocol.body = #"{"code":0,"data":{"model":"wanted","hours":24,"coverage":{"start":"2026-10-18T00:00:00Z","end":"2026-10-19T00:00:00Z"},"summary":{"metric_sample_count":0}}}"#
        let noMetrics = try await api.performance(modelID: "wanted")
        XCTAssertNil(noMetrics.summary?.tokensPerSecond)
    }

    func testOnlySelectedModelsArePolledAndManualRefreshCannotBypassCooldown() async {
        let api = PerformanceFixture()
        let suite = "performance-cooldown-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var clock = Date(timeIntervalSince1970: 10_000)
        let store = WikiVibePerformanceStore(api: api, defaults: defaults, now: { clock })
        await store.refresh()
        XCTAssertEqual(Set(store.readings.keys), ["first"])
        await api.failFirst()
        await store.refresh()
        XCTAssertTrue(store.failedIDs.isEmpty)
        store.setSelected("second", enabled: true)
        await store.refresh()
        XCTAssertEqual(store.readings["second"]?.summary?.tokensPerSecond, 40)
        XCTAssertTrue(store.failedIDs.isEmpty)
        clock.addTimeInterval(61)
        await store.refresh()
        XCTAssertEqual(store.failedIDs, ["first"])
        XCTAssertFalse(store.isStale("second"))
        store.setSelected("second", enabled: false)
        clock.addTimeInterval(901)
        XCTAssertTrue(store.isStale("second"))
        XCTAssertEqual(store.readings["second"]?.summary?.tokensPerSecond, 40)
    }

    func testOldAndFutureSuccessfulReadingsStayStale() {
        let end = Date(timeIntervalSince1970: 10_000)
        let reading = WikiVibePerformanceReading(model: "first", hours: 24,
            coverage: .init(start: end.addingTimeInterval(-86400), end: end), summary: nil)
        XCTAssertTrue(reading.isFresh(at: end.addingTimeInterval(900)))
        XCTAssertFalse(reading.isFresh(at: end.addingTimeInterval(901)))
        XCTAssertTrue(reading.isFresh(at: end.addingTimeInterval(-300)))
        XCTAssertFalse(reading.isFresh(at: end.addingTimeInterval(-301)))
    }
}

private actor PerformanceFixture: WikiVibePerformanceAPIInterface {
    private var firstFailed = false
    private var catalogFailed = false
    func failFirst() { firstFailed = true }
    func failCatalog() { catalogFailed = true }
    func models() async throws -> [WikiVibePerformanceModel] {
        if catalogFailed { throw URLError(.notConnectedToInternet) }
        return [.init(id: "first", displayName: "First"), .init(id: "second", displayName: "Second")]
    }
    func performance(modelID: String) async throws -> WikiVibePerformanceReading {
        if firstFailed && modelID == "first" { throw URLError(.timedOut) }
        return .init(model: modelID, hours: 24,
                     coverage: .init(start: Date(timeIntervalSince1970: -76400), end: Date(timeIntervalSince1970: 10000)),
                     summary: .init(metricSampleCount: 3, avgTokensPerSec: firstFailed ? 40 : 20, avgTtftMs: 1000))
    }
}

private final class PerformanceProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var body = ""
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
