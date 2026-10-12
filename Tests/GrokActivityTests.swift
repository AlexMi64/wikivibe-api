import XCTest
@testable import Codenotch

/// A headless run's turn, read off its `updates.jsonl`: open until
/// `turn_completed`, whatever hook runs follow it.
final class GrokHeadlessTurnTests: XCTestCase {
    private func update(_ kind: String, hook: String? = nil) -> String {
        let event = hook.map { #","event_name":"\#($0)""# } ?? ""
        return #"{"timestamp":1789752783,"method":"_x.ai/session/update","params":{"sessionId":"s","update":{"sessionUpdate":"\#(kind)"\#(event)}}}"#
    }

    private func tail(_ lines: [String]) -> Data {
        Data(lines.joined(separator: "\n").utf8)
    }

    func testATurnUnderWayIsOpen() {
        XCTAssertTrue(GrokActivity.turnIsOpen(inTail: tail([
            update("hook_execution", hook: "session_start"),
            update("user_message_chunk"),
            update("agent_thought_chunk"),
        ])))
    }

    /// Grok runs its `stop` hooks after `turn_completed`, so the last line of
    /// a finished run is a hook, not the turn's end.
    func testACompletedTurnIsClosedWithStopHooksAfterIt() {
        XCTAssertFalse(GrokActivity.turnIsOpen(inTail: tail([
            update("user_message_chunk"),
            update("agent_message_chunk"),
            update("turn_completed"),
            update("hook_execution", hook: "stop"),
        ])))
    }

    func testAPromptWithOnlyItsHooksSoFarIsOpen() {
        XCTAssertTrue(GrokActivity.turnIsOpen(inTail: tail([
            update("hook_execution", hook: "session_start"),
            update("hook_execution", hook: "user_prompt_submit"),
        ])))
    }

    /// A live run that has written no update yet has only just started it.
    func testARunThatHasWrittenNothingYetIsOpen() {
        XCTAssertTrue(GrokActivity.turnIsOpen(inTail: Data()))
    }

    /// The 64 KB window can start mid-line. A fragment is not a record, even
    /// one that happens to contain `turn_completed`; with only hooks after
    /// it, a run that is still alive is still in its turn.
    func testALineCutByTheTailWindowIsNotReadAsARecord() {
        XCTAssertTrue(GrokActivity.turnIsOpen(inTail: tail([
            #"sessionUpdate":"turn_completed"}}}"#,
            update("hook_execution", hook: "stop"),
        ])))
    }
    /// The sequence a real `grok -p` run wrote (grok 1.0.34): a `stop` hook
    /// fires mid-turn too, before the answer, and must not end the turn.
    func testARealRunIsOpenUntilItsTurnCompletes() {
        let run = [
            update("hook_execution", hook: "session_start"),
            update("hook_execution", hook: "user_prompt_submit"),
            update("user_message_chunk"),
            update("agent_thought_chunk"),
            update("hook_execution", hook: "stop"),
            update("agent_message_chunk"),
        ]
        XCTAssertTrue(GrokActivity.turnIsOpen(inTail: tail(run)))
        XCTAssertFalse(GrokActivity.turnIsOpen(inTail: tail(run + [
            update("turn_completed"),
            update("hook_execution", hook: "stop"),
        ])))
    }
}

/// Headless runs are never in `active_sessions.json`; each is found from its
/// process, through the session it holds open.
final class GrokHeadlessSessionTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GrokHeadlessSessionTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var sessionsRoot: URL { root.appendingPathComponent("sessions") }

    private func session(_ id: String, kind: String? = "headless", completed: Bool = false) throws -> URL {
        let directory = sessionsRoot.appendingPathComponent("%2FUsers%2Fme%2Fcode%2Fapp").appendingPathComponent(id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let kind {
            try Data(#"{"session_kind":"\#(kind)"}"#.utf8).write(to: directory.appendingPathComponent("summary.json"))
        }
        var lines = [#"{"params":{"update":{"sessionUpdate":"user_message_chunk"}}}"#]
        if completed {
            lines.append(#"{"params":{"update":{"sessionUpdate":"turn_completed"}}}"#)
            lines.append(#"{"params":{"update":{"sessionUpdate":"hook_execution","event_name":"stop"}}}"#)
        }
        try Data(lines.joined(separator: "\n").utf8).write(to: directory.appendingPathComponent("updates.jsonl"))
        try Data().write(to: directory.appendingPathComponent("events.jsonl"))
        return directory
    }

    private func process(_ pid: pid_t, holding sessions: [URL]) -> GrokActivity.Process {
        GrokActivity.Process(pid: pid, startedAt: Date(timeIntervalSince1970: 1_800_000_000),
                             cwd: "/Users/me/code/app", openSessions: sessions)
    }

    func testAHeadlessRunMidTurnIsBusyWithItsProcess() throws {
        let run = try session("run-1")
        let found = GrokActivity.headless(processes: [process(4242, holding: [run])])
        XCTAssertEqual(found.map(\.id), ["grok.run-1"])
        XCTAssertEqual(found.first?.state, .busy)
        XCTAssertEqual(found.first?.name, "app")
        XCTAssertEqual(found.first?.processID, 4242)
    }

    /// A headless run exits right after its turn; until it does, it is done.
    func testACompletedTurnShowsNothing() throws {
        let run = try session("run-1", completed: true)
        XCTAssertTrue(GrokActivity.headless(processes: [process(4242, holding: [run])]).isEmpty)
    }

    /// An earlier run in the same directory, already finished, sits beside
    /// the live one. The live process holds only its own session.
    func testAFinishedRunBesideTheLiveOneDoesNotHideIt() throws {
        _ = try session("earlier", completed: true)
        let live = try session("live")
        XCTAssertEqual(GrokActivity.headless(processes: [process(4242, holding: [live])]).map(\.id),
                       ["grok.live"])
    }

    /// A run with subagents holds their sessions open too; the run is its own,
    /// whether a subagent's summary says so already or is not written yet,
    /// and whichever the process opened first.
    func testASubagentSessionItHoldsIsNotTheRun() throws {
        let finished = try session("sub-1", kind: "subagent", completed: true)
        let unnamed = try session("sub-2", kind: nil)
        let run = try session("run-1")
        XCTAssertEqual(GrokActivity.headless(processes: [process(4242, holding: [finished, unnamed, run])]).map(\.id),
                       ["grok.run-1"])
    }

    /// A TUI holds its session open as a headless run does. Not yet in the
    /// registry (it is written after the session is opened), sitting at its
    /// prompt, it must not show as working.
    func testATUINotYetInTheRegistryIsNotAHeadlessRun() throws {
        let tui = try session("tui-1", kind: nil)
        XCTAssertTrue(GrokActivity.headless(processes: [process(4242, holding: [tui])]).isEmpty)
    }

    /// Starting up, before it has opened its session.
    func testARunHoldingNoSessionYetShowsNothing() {
        XCTAssertTrue(GrokActivity.headless(processes: [process(4242, holding: [])]).isEmpty)
    }

    /// Runs fanned out in one directory each hold their own session.
    func testRunsStartedTogetherInOneDirectoryAreEachShown() throws {
        let a = try session("run-a")
        let b = try session("run-b")
        let found = GrokActivity.headless(processes: [process(1, holding: [a]), process(2, holding: [b])])
        XCTAssertEqual(found.map(\.id), ["grok.run-a", "grok.run-b"])
        XCTAssertEqual(found.map(\.processID), [1, 2])
    }

    /// The real lookup, against this test's own process: holding a session's
    /// `events.jsonl` open is what names it; a file elsewhere is ignored.
    func testTheSessionAProcessHoldsOpenIsFound() throws {
        let run = try session("run-1")
        let held = try FileHandle(forWritingTo: run.appendingPathComponent("events.jsonl"))
        defer { try? held.close() }
        let elsewhere = root.appendingPathComponent("events.jsonl")
        try Data().write(to: elsewhere)
        let other = try FileHandle(forWritingTo: elsewhere)
        defer { try? other.close() }

        // The temporary directory is under `/var`, a symlink to `/private/var`,
        // so this also covers a root reached through a symlink.
        func real(_ url: URL) -> String {
            guard let resolved = realpath(url.path, nil) else { return url.path }
            defer { free(resolved) }
            return String(cString: resolved)
        }
        let found = GrokActivity.openSessions(of: getpid(), under: sessionsRoot)
        XCTAssertEqual(found.map(real), [real(run)])
    }

    /// A TUI is read from the registry; its process, which Grok's process
    /// listing also finds, must not be read again as a headless run.
    func testARegisteredTUIIsNotCountedTwice() throws {
        let tui = try session("tui-1", kind: nil)
        let active = root.appendingPathComponent("active_sessions.json")
        let pid = getpid()
        try Data(#"[{"session_id":"tui-1","pid":\#(pid),"cwd":"/Users/me/code/app"}]"#.utf8).write(to: active)

        let found = GrokActivity.read(activeURL: active, sessionsRoot: sessionsRoot, staleAfter: 45,
                                      processes: { [self.process(pid, holding: [tui])] })
        XCTAssertEqual(found.map(\.id), ["grok.tui-1"])
    }

    /// Grok is started through `~/.grok/bin/grok` or its `agent` alias, both
    /// links to a versioned binary; the name is only a first cut, the path
    /// decides.
    func testGrokIsRecognisedByNameThenByItsBinary() {
        XCTAssertTrue(GrokActivity.isGrokName("grok"))
        XCTAssertTrue(GrokActivity.isGrokName("agent"))
        XCTAssertTrue(GrokActivity.isGrokName("grok-1.0.34-mac"))
        XCTAssertFalse(GrokActivity.isGrokName("claude"))
        XCTAssertTrue(GrokActivity.isGrokBinary(path: "/Users/me/.grok/downloads/grok-1.0.34-macos-aarch64"))
        XCTAssertFalse(GrokActivity.isGrokBinary(path: "/usr/local/bin/agent"))
    }

    /// Someone who only ever runs Grok headless has no registry at all, or
    /// one Grok left half-written; neither may hide the runs.
    func testHeadlessRunsAreFoundWithoutAUsableRegistry() throws {
        let run = try session("run-1")
        let broken = root.appendingPathComponent("broken.json")
        try Data(#"{"not":"a list"#.utf8).write(to: broken)
        for registry in [root.appendingPathComponent("missing.json"), broken] {
            let found = GrokActivity.read(activeURL: registry, sessionsRoot: sessionsRoot, staleAfter: 45,
                                          processes: { [self.process(4242, holding: [run])] })
            XCTAssertEqual(found.map(\.id), ["grok.run-1"], registry.lastPathComponent)
        }
    }
}
