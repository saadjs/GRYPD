import Foundation

/// Aggregate stats for the History summary header. Pure functions over the log
/// list (+ catalog for durations) so they're unit-testable and view-agnostic.
enum HistoryStats {

    /// A Monday-based calendar, so weeks run Mon–Sun as the streak rule expects.
    static func weekCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2 // Monday
        return cal
    }

    /// Start of the Mon–Sun week containing `date`.
    static func weekStart(_ date: Date, _ cal: Calendar) -> Date? {
        cal.dateInterval(of: .weekOfYear, for: date)?.start
    }

    /// Sessions performed in the current week.
    static func thisWeekCount(_ logs: [WorkoutLog], now: Date = .now,
                              cal: Calendar = weekCalendar()) -> Int {
        guard let interval = cal.dateInterval(of: .weekOfYear, for: now) else { return 0 }
        return logs.filter { interval.contains($0.performedAt) }.count
    }

    /// Consecutive Mon–Sun weeks with ≥1 session, counting back from now. A gap
    /// week breaks the streak; the current (in-progress) week never breaks it —
    /// it simply doesn't count until it has a session.
    static func streakWeeks(_ logs: [WorkoutLog], now: Date = .now,
                            cal: Calendar = weekCalendar()) -> Int {
        guard !logs.isEmpty else { return 0 }
        let weeksWithLogs = Set(logs.compactMap { weekStart($0.performedAt, cal) })
        guard var cursor = weekStart(now, cal) else { return 0 }

        // If the current week has no session yet, don't break — start from last week.
        if !weeksWithLogs.contains(cursor) {
            guard let prev = cal.date(byAdding: .weekOfYear, value: -1, to: cursor) else { return 0 }
            cursor = prev
        }

        var streak = 0
        while weeksWithLogs.contains(cursor) {
            streak += 1
            guard let prev = cal.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }

    /// Total minutes across all sessions, from the catalog's nominal duration
    /// for each logged workout. Sessions whose workout left the catalog
    /// contribute 0.
    @MainActor
    static func totalMinutes(_ logs: [WorkoutLog], catalog: CatalogStore) -> Int {
        logs.reduce(0) { sum, log in
            sum + (catalog.workout(id: log.workoutId)?.durationMinutes ?? 0)
        }
    }

    /// Compact time label for the header, e.g. "0m", "45m", "41h".
    static func timeLabel(minutes: Int) -> String {
        minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h"
    }

    /// Sessions grouped by calendar month, newest month first, each group's logs
    /// newest first. Returns a stable id (month start) plus a display label.
    static func byMonth(_ logs: [WorkoutLog],
                        cal: Calendar = Calendar(identifier: .gregorian))
        -> [(id: Date, label: String, logs: [WorkoutLog])] {
        let grouped = Dictionary(grouping: logs) { log -> Date in
            cal.dateInterval(of: .month, for: log.performedAt)?.start ?? log.performedAt
        }
        return grouped
            .map { (id: $0.key,
                    label: monthLabel($0.key),
                    logs: $0.value.sorted { $0.performedAt > $1.performedAt }) }
            .sorted { $0.id > $1.id }
    }

    private static func monthLabel(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year()).uppercased()
    }
}
