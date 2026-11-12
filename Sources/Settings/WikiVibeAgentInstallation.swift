import Foundation

extension WikiVibeAgent {
    var executableName: String {
        switch self {
        case .codex: return "codex"
        case .omp: return "omp"
        case .opencode: return "opencode"
        case .claude: return "claude"
        case .pi: return "pi"
        case .qwen: return "qwen"
        case .droid: return "droid"
        }
    }
    var homepage: URL {
        switch self {
        case .codex: return URL(string: "https://github.com/openai/codex")!
        case .omp: return URL(string: "https://omp.sh")!
        case .opencode: return URL(string: "https://opencode.ai/v1/docs/")!
        case .claude: return URL(string: "https://code.claude.com/docs/en/setup")!
        case .pi: return URL(string: "https://pi.dev")!
        case .qwen: return URL(string: "https://qwenlm.github.io/qwen-code-docs/")!
        case .droid: return URL(string: "https://docs.factory.com/droid-cli/quickstart")!
        }
    }
    // Fixed official installers only. No model ID, URL, key or user text is interpolated into shell code.
    // npm's prefix stays user-writable; no sudo or global system-prefix mutation.
    var installCommand: String {
        switch self {
        case .codex: return "npm install --global --prefix \"$HOME/.local\" @openai/codex"
        case .omp: return "curl -fsSL https://omp.sh/install | sh -s -- --binary"
        case .opencode: return "npm install --global --prefix \"$HOME/.local\" opencode-ai@1"
        case .claude: return "curl -fsSL https://claude.ai/install.sh | bash"
        case .pi: return "npm install --global --ignore-scripts --prefix \"$HOME/.local\" @earendil-works/pi-coding-agent"
        case .qwen: return "npm install --global --prefix \"$HOME/.local\" @qwen-code/qwen-code"
        case .droid: return "npm install --global --prefix \"$HOME/.local\" droid"
        }
    }
}

protocol WikiVibeAgentInstalling: Sendable {
    func executable(for agent: WikiVibeAgent) -> URL?
    func install(_ agent: WikiVibeAgent) async throws
}

enum WikiVibeAgentInstallationError: Error, LocalizedError {
    case failed, executableMissing
    var errorDescription: String? {
        switch self {
        case .failed: return L10n.t("Installation failed. Agent settings were not written. Check the official installation instructions.")
        case .executableMissing: return L10n.t("The agent executable could not be verified. Agent settings were not written.")
        }
    }
}

struct WikiVibeAgentInstallationService: WikiVibeAgentInstalling {
    let home: URL
    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) { self.home = home }
    private var searchDirectories: [String] {
        [home.appendingPathComponent(".local/bin").path, home.appendingPathComponent(".bun/bin").path,
         home.appendingPathComponent(".omp/bin").path, home.appendingPathComponent(".opencode/bin").path,
         "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
    }
    func executable(for agent: WikiVibeAgent) -> URL? {
        searchDirectories.lazy.map { URL(fileURLWithPath: $0).appendingPathComponent(agent.executableName) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
    func install(_ agent: WikiVibeAgent) async throws {
        if executable(for: agent) == nil {
            // pipefail prevents an empty/failed download being reported as a successful installer.
            try await run(URL(fileURLWithPath: "/bin/bash"), ["-o", "pipefail", "-c", agent.installCommand], timeout: 600)
        }
        guard let binary = executable(for: agent) else { throw WikiVibeAgentInstallationError.executableMissing }
        try await run(binary, ["--version"], timeout: 15)
    }
    private func run(_ executable: URL, _ arguments: [String], timeout: TimeInterval) async throws {
        let environment = ["HOME": home.path, "PATH": searchDirectories.joined(separator: ":"), "LANG": "en_US.UTF-8"]
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                process.environment = environment
                process.currentDirectoryURL = home
                process.standardInput = FileHandle.nullDevice
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
                do {
                    try process.run()
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
                    process.waitUntilExit()
                    deadline.cancel()
                    guard process.terminationStatus == 0 else { throw WikiVibeAgentInstallationError.failed }
                    continuation.resume()
                } catch {
                    deadline.cancel()
                    if process.isRunning { process.terminate() }
                    continuation.resume(throwing: WikiVibeAgentInstallationError.failed)
                }
            }
        }
    }
}
