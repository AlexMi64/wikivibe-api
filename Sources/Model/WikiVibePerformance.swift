import Combine
import Foundation

/// Public gateway measurements, independent of account and inference credentials.
struct WikiVibePerformanceModel: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    enum CodingKeys: String, CodingKey { case id; case displayName = "display_name" }
}

struct WikiVibePerformanceReading: Decodable, Equatable, Sendable {
    struct Coverage: Decodable, Equatable, Sendable { let start: Date; let end: Date }
    struct Summary: Decodable, Equatable, Sendable {
        let metricSampleCount: Int
        let avgTokensPerSec: Double?
        let avgTtftMs: Double?
        enum CodingKeys: String, CodingKey {
            case metricSampleCount = "metric_sample_count"
            case avgTokensPerSec = "avg_tokens_per_sec"
            case avgTtftMs = "avg_ttft_ms"
        }
        var tokensPerSecond: Double? {
            guard metricSampleCount > 0, let value = avgTokensPerSec, value.isFinite, value >= 0 else { return nil }
            return value
        }
        var firstTokenSeconds: Double? {
            guard metricSampleCount > 0, let value = avgTtftMs, value.isFinite, value >= 0 else { return nil }
            return value / 1000
        }
    }
    let model: String
    let hours: Int
    let coverage: Coverage
    let summary: Summary?

    /// Polling tolerates a short outage, not a historical cached success.
    func isFresh(at now: Date) -> Bool {
        let age = now.timeIntervalSince(coverage.end)
        return age >= -300 && age <= 900
    }
}

protocol WikiVibePerformanceAPIInterface: Sendable {
    func models() async throws -> [WikiVibePerformanceModel]
    func performance(modelID: String) async throws -> WikiVibePerformanceReading
}

struct WikiVibePerformanceAPI: WikiVibePerformanceAPIInterface {
    enum Failure: Error { case response }
    private let session: URLSession
    private static let base = URL(string: "https://api.wikivibe.dev/api/v1/marketplace/models")!

    init(session: URLSession? = nil) {
        if let session { self.session = session; return }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        self.session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    private struct Envelope<T: Decodable>: Decodable { let code: Int; let data: T? }
    private struct Group: Decodable { let models: [WikiVibePerformanceModel] }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { throw Failure.response }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: text) else { throw Failure.response }
            return date
        }
        let envelope = try decoder.decode(Envelope<T>.self, from: data)
        guard envelope.code == 0, let value = envelope.data else { throw Failure.response }
        return value
    }

    func models() async throws -> [WikiVibePerformanceModel] {
        let groups: [Group] = try await get(Self.base)
        var seen = Set<String>()
        return groups.flatMap(\.models).filter { !$0.id.isEmpty && seen.insert($0.id).inserted }
    }

    func performance(modelID: String) async throws -> WikiVibePerformanceReading {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        guard !modelID.isEmpty, let encoded = modelID.addingPercentEncoding(withAllowedCharacters: allowed) else { throw Failure.response }
        let url = URL(string: Self.base.absoluteString + "/" + encoded + "/performance?hours=24")!
        let reading: WikiVibePerformanceReading = try await get(url)
        guard reading.model == modelID, reading.hours == 24,
              reading.coverage.start <= reading.coverage.end,
              reading.summary.map({ $0.metricSampleCount >= 0 }) ?? true else { throw Failure.response }
        return reading
    }
}

@MainActor
final class WikiVibePerformanceStore: ObservableObject {
    @Published private(set) var models: [WikiVibePerformanceModel] = []
    @Published private(set) var readings: [String: WikiVibePerformanceReading] = [:]
    @Published private(set) var failedIDs = Set<String>()
    @Published private(set) var isRefreshing = false
    @Published private(set) var catalogFailed = false
    @Published private(set) var selectedIDs: [String]
    private let api: WikiVibePerformanceAPIInterface
    private let defaults: UserDefaults
    private static let selectionKey = "widget.serverPerformanceModels"
    private var polling: Task<Void, Never>?
    private let now: () -> Date
    private var catalogAttemptedAt: Date?
    private var catalogLoadedAt: Date?
    private var attemptedAt: [String: Date] = [:]

    init(api: WikiVibePerformanceAPIInterface = WikiVibePerformanceAPI(), defaults: UserDefaults = .standard,
         now: @escaping () -> Date = Date.init) {
        self.api = api
        self.defaults = defaults
        self.now = now
        selectedIDs = defaults.stringArray(forKey: Self.selectionKey) ?? []
    }

    func setSelected(_ id: String, enabled: Bool) {
        guard models.contains(where: { $0.id == id }) else { return }
        if enabled {
            if !selectedIDs.contains(id) { selectedIDs.append(id) }
        } else {
            selectedIDs.removeAll { $0 == id }
        }
        defaults.set(selectedIDs, forKey: Self.selectionKey)
    }

    func start() {
        guard polling == nil else { return }
        polling = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                do { try await Task.sleep(for: .seconds(300)) } catch { return }
            }
        }
    }

    func stop() { polling?.cancel(); polling = nil }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        if catalogLoadedAt.map({ now().timeIntervalSince($0) >= 3600 }) ?? true,
           catalogAttemptedAt.map({ now().timeIntervalSince($0) >= 60 }) ?? true {
            catalogAttemptedAt = now()
            do {
                let catalog = try await api.models()
                try Task.checkCancellation()
                models = catalog
                catalogFailed = false
                catalogLoadedAt = now()
                let ids = Set(catalog.map(\.id))
                readings = readings.filter { ids.contains($0.key) }
                attemptedAt = attemptedAt.filter { ids.contains($0.key) }
                failedIDs.formIntersection(ids)
                // Start with one cell; an explicitly empty selection stays empty.
                if defaults.object(forKey: Self.selectionKey) == nil, let first = catalog.first {
                    setSelected(first.id, enabled: true)
                }
            } catch {
                guard !Task.isCancelled else { return }
                catalogFailed = true
            }
        }
        // Re-evaluate selection after each await. No full-catalog performance fan-out.
        var visited = Set<String>()
        while !Task.isCancelled, let model = models.first(where: {
            selectedIDs.contains($0.id) && !visited.contains($0.id)
                && (attemptedAt[$0.id].map { now().timeIntervalSince($0) >= 60 } ?? true)
        }) {
            attemptedAt[model.id] = now()
            visited.insert(model.id)
            do {
                let reading = try await api.performance(modelID: model.id)
                try Task.checkCancellation()
                readings[model.id] = reading
                failedIDs.remove(model.id)
            } catch {
                guard !Task.isCancelled else { return }
                failedIDs.insert(model.id)
            }
        }
    }

    func speedText(for id: String) -> String {
        guard let value = readings[id]?.summary?.tokensPerSecond else { return "— tok/s" }
        return value > 0 && value < 0.1 ? "<0.1 tok/s" : value.formatted(.number.precision(.fractionLength(0...1))) + " tok/s"
    }

    func isStale(_ id: String) -> Bool {
        catalogFailed || failedIDs.contains(id) || readings[id].map { !$0.isFresh(at: now()) } == true
    }

    var snapshots: [ProviderSnapshot] {
        selectedIDs.compactMap { id in
            guard let model = models.first(where: { $0.id == id }) else { return nil }
            let reading = readings[id]
            let stale = isStale(id)
            let status: ProviderStatus = stale
                ? reading.map { .stale(since: $0.coverage.end) } ?? .error(L10n.t("Could not load server performance."))
                : .ok
            var rows = [metric("server-tps", L10n.t("TPS including first-token wait"), speedText(for: id))]
            if let reading {
                if let summary = reading.summary {
                    rows.append(metric("samples", L10n.t("Metric samples"), summary.metricSampleCount.formatted()))
                }
                if let seconds = reading.summary?.firstTokenSeconds {
                    rows.append(metric("ttft", L10n.t("First token"), seconds.formatted(.number.precision(.fractionLength(0...1))) + " s"))
                }
                rows.append(metric("as-of", L10n.t("As of"), reading.coverage.end.formatted(date: .abbreviated, time: .shortened)))
            }
            if stale { rows.append(metric("stale", L10n.t("Status"), L10n.t(reading == nil ? "Could not load server performance." : "Reading is stale; check its date."))) }
            else if reading == nil { rows.append(metric("loading", L10n.t("Status"), L10n.t("Loading server performance…"))) }
            return ProviderSnapshot(id: "wikivibe-tps:" + id, displayName: model.displayName, glyph: .wikivibe,
                                    fidelity: .official, status: status, windows: rows,
                                    plan: L10n.t("Public traffic · 24 h · not your request"))
        }
    }
    private func metric(_ id: String, _ label: String, _ text: String) -> LimitWindow {
        LimitWindow(id: id, label: label, usedText: text, detail: text)
    }
}
