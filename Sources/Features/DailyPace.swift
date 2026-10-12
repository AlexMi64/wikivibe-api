import Foundation

/// A day's share of Claude's weekly allowance, drawn as a ring of its own.
///
/// The weekly limit is the one that actually runs out, and the way to make it
/// last is to spend about a seventh of it a day. This turns that rule into a
/// window: the allowance available so far is `(days elapsed + 1) / 7` — a
/// whole day's share arrives at the start of each day, counted from the
/// moment the weekly window opened — and the ring is what has been used
/// against it. A quiet day leaves room for the next; a heavy one shows up as
/// the ring filling, and at 100% the ordinary threshold and limit alerts fire
/// exactly as they do for a window the vendor reports.
///
/// Days are counted from the weekly reset rather than from midnight, so the
/// seven shares are equal and the last one ends precisely when the week does.
enum DailyPace {
    /// The synthetic window's id. Never one a provider reports.
    static let windowID = "daily_pace"
    static let dayLength: TimeInterval = 86_400
    static let days = 7
    static let weekLength: TimeInterval = Double(days) * dayLength

    struct Reading: Equatable {
        /// Used against today's cumulative share, 0...1+.
        let usedFraction: Double
        /// The share of the week available so far: 1/7 on the first day, 1 on the last.
        let allowedFraction: Double
        /// Zero-based day of the week, 0...6.
        let dayIndex: Int
        /// When the next share arrives — the weekly reset itself on the last day.
        let dayEndsAt: Date
    }

    /// Nil when the weekly window has no reading or no reset to count from.
    static func reading(weekly: LimitWindow, now: Date) -> Reading? {
        guard let used = weekly.usedFraction, used.isFinite, used >= 0,
              let resetsAt = weekly.resetsAt else { return nil }
        let start = resetsAt.addingTimeInterval(-weekLength)
        // Provider and device clocks can disagree by a little in either
        // direction; neither a negative day nor an eighth one is a real reading.
        let elapsed = min(max(now.timeIntervalSince(start), 0), weekLength)
        let dayIndex = min(days - 1, Int(elapsed / dayLength))
        let allowed = Double(dayIndex + 1) / Double(days)
        let dayEnds = dayIndex == days - 1
            ? resetsAt
            : start.addingTimeInterval(Double(dayIndex + 1) * dayLength)
        return Reading(usedFraction: used / allowed, allowedFraction: allowed,
                       dayIndex: dayIndex, dayEndsAt: dayEnds)
    }

    /// The window the ring draws. No `duration`, on purpose: the tooltip's
    /// pace line compares a window with the time left in it, and a window that
    /// *is* a pace has nothing to be compared against.
    static func window(weekly: LimitWindow, now: Date) -> LimitWindow? {
        guard let reading = reading(weekly: weekly, now: now) else { return nil }
        return LimitWindow(id: windowID, label: L10n.t("Daily pace"),
                           usedFraction: reading.usedFraction, resetsAt: reading.dayEndsAt)
    }

    /// The snapshot with the daily window leading it: the big ring becomes the
    /// day's pace, the thin ring — where one is switched on — the session, and
    /// the weekly window stays in the card. Anything but a Claude snapshot
    /// with a weekly reading is returned untouched, and so is a snapshot that
    /// already carries the window: the store re-publishes what it archived.
    static func apply(to snapshot: ProviderSnapshot, now: Date) -> ProviderSnapshot {
        guard ClaudeProfile.isClaude(providerID: snapshot.providerID),
              !snapshot.windows.contains(where: { $0.id == windowID }),
              let weekly = snapshot.windows.first(where: { $0.id == "weekly_all" }),
              let daily = window(weekly: weekly, now: now) else { return snapshot }
        var paced = snapshot
        paced.windows.insert(daily, at: 0)
        paced.headlineID = windowID
        paced.weeklyID = snapshot.windows.contains { $0.id == "session" } ? "session" : nil
        return paced
    }

    static func apply(to snapshots: [ProviderSnapshot], enabled: Bool,
                      now: Date = Date()) -> [ProviderSnapshot] {
        guard enabled else { return snapshots }
        return snapshots.map { apply(to: $0, now: now) }
    }
}
