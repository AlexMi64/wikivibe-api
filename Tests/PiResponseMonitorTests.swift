import XCTest
@testable import Codenotch

final class PiResponseMonitorTests: XCTestCase {
    private var directory: URL!
    private var session: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiResponseMonitorTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        session = directory.appendingPathComponent("session.jsonl")
        try Data().write(to: session)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func message(id: String, provider: String, model: String? = nil,
                         stop: String = "stop") -> String {
        let model = model ?? (provider == "xai" ? "grok-4.7" : "gpt-5.6-sol")
        return #"{"type":"message","id":"\#(id)","message":{"role":"assistant","provider":"\#(provider)","model":"\#(model)","stopReason":"\#(stop)","timestamp":1800000000000}}"#
    }

    private func user(id: String = "user") -> String {
        #"{"type":"message","id":"\#(id)","message":{"role":"user","timestamp":1800000000000}}"#
    }

    private func modelChange(provider: String, model: String) -> String {
        #"{"type":"model_change","id":"model","provider":"\#(provider)","modelId":"\#(model)"}"#
    }

    private func append(_ text: String) throws {
        let handle = try FileHandle(forWritingTo: session)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    func testCompletedCodexAndGrokResponsesMapToTheirUsageProviders() throws {
        try append(message(id: "codex", provider: "openai-codex") + "\n"
            + message(id: "grok", provider: "xai") + "\n")

        let result = PiSessionTailReader(startedAt: .distantPast).consume(session)
        XCTAssertEqual(result.completedUsageProviderIDs, Set(["codex", "grok"]))
    }

    func testSeveralCompletedResponsesForOneProviderCoalesce() throws {
        try append(message(id: "one", provider: "xai") + "\n"
            + message(id: "two", provider: "xai") + "\n")

        let result = PiSessionTailReader(startedAt: .distantPast).consume(session)
        XCTAssertEqual(result.completedUsageProviderIDs, Set(["grok"]))
    }

    func testIntermediateAndUnrelatedRecordsDoNotRefreshUsage() throws {
        try append(message(id: "tool", provider: "xai", stop: "toolUse") + "\n"
            + message(id: "pending", provider: "openai-codex", stop: "pending") + "\n"
            + message(id: "claude", provider: "anthropic", model: "claude-sonnet-5") + "\n"
            + #"{"type":"custom","id":"stamp","customType":"pi-stamp"}"# + "\n"
            + #"{"type":"message","id":"result","message":{"role":"toolResult"}}"# + "\n")

        let result = PiSessionTailReader(startedAt: .distantPast).consume(session)
        XCTAssertTrue(result.completedUsageProviderIDs.isEmpty)
    }

    func testPartialLineIsKeptUntilTheNextAppend() throws {
        let record = message(id: "split", provider: "xai")
        let split = record.index(record.startIndex, offsetBy: record.count / 2)
        let reader = PiSessionTailReader(startedAt: .distantPast)

        try append(String(record[..<split]))
        XCTAssertTrue(reader.consume(session).completedUsageProviderIDs.isEmpty)

        try append(String(record[split...]) + "\n")
        XCTAssertEqual(reader.consume(session).completedUsageProviderIDs, Set(["grok"]))
    }

    func testTruncatedFileResetsItsCursorWithoutRepeatingSeenEntries() throws {
        let reader = PiSessionTailReader(startedAt: .distantPast)
        try append(message(id: "first", provider: "xai") + "\n" + String(repeating: " ", count: 200))
        XCTAssertEqual(reader.consume(session).completedUsageProviderIDs, Set(["grok"]))

        try Data((message(id: "second", provider: "openai-codex") + "\n").utf8).write(to: session)
        XCTAssertEqual(reader.consume(session).completedUsageProviderIDs, Set(["codex"]))
        XCTAssertTrue(reader.consume(session).completedUsageProviderIDs.isEmpty)
    }

    func testResponsesOlderThanTheMonitorAreIgnored() throws {
        try append(message(id: "old", provider: "xai") + "\n")
        let afterFixture = Date(timeIntervalSince1970: 1_800_000_001)
        let result = PiSessionTailReader(startedAt: afterFixture).consume(session)
        XCTAssertTrue(result.completedUsageProviderIDs.isEmpty)
        XCTAssertTrue(result.activityEvents.isEmpty)
    }

    func testTurnStartsFromSelectedModelAndEndsOnFinalAssistant() throws {
        let reader = PiSessionTailReader(startedAt: .distantPast)
        try append(modelChange(provider: "radius", model: "claude-sonnet-5") + "\n" + user() + "\n")
        let started = reader.consume(session).activityEvents
        XCTAssertEqual(started.map(\.providerID), ["claude"])
        XCTAssertEqual(started.map(\.isBusy), [true])

        try append(message(id: "tool", provider: "radius", model: "claude-sonnet-5",
                           stop: "toolUse") + "\n")
        XCTAssertEqual(reader.consume(session).activityEvents.map(\.isBusy), [true])

        try append(message(id: "done", provider: "radius", model: "claude-sonnet-5") + "\n")
        let finished = reader.consume(session).activityEvents
        XCTAssertEqual(finished.map(\.providerID), ["claude"])
        XCTAssertEqual(finished.map(\.isBusy), [false])
    }

    func testBuiltInModelFamiliesMapToTheirCards() {
        let mappings = [
            ("radius", "claude-opus-5", "claude"),
            ("radius", "deepseek-v4-pro", "deepseek"),
            ("radius", "gemini-3-pro", "gemini-api"),
            ("radius", "glm-5.3", "glm"),
            ("radius", "gpt-5.6-sol", "codex"),
            ("xai", "grok-4.7", "grok"),
            ("radius", "kimi-k3", "kimi"),
            ("minimax", "MiniMax-M2", "minimax"),
            ("ollama", "qwen3", "ollama-local"),
            ("github-copilot", "gpt-5", "copilot"),
        ]
        for (provider, model, expected) in mappings {
            XCTAssertEqual(PiProviderMapping.activityProviderID(provider: provider, model: model),
                           expected, "\(provider)/\(model)")
        }
        XCTAssertNil(PiProviderMapping.activityProviderID(provider: "radius", model: "balanced"))
    }
}
