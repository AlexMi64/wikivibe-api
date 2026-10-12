import os

/// An agent app has no window to print into, so anything worth diagnosing has
/// to go somewhere you can read it:
///
///     log stream --predicate 'subsystem == "dev.wikivibe.desktop"' --level debug
enum Log {
    static let usage = Logger(subsystem: "dev.wikivibe.desktop", category: "usage")
    static let sessions = Logger(subsystem: "dev.wikivibe.desktop", category: "sessions")
}
