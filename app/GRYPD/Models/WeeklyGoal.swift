import Foundation
import SwiftData

enum WorkoutBodyFocus: String, Codable, CaseIterable {
    case upperBody = "upper-body"
    case lowerBody = "lower-body"
    case totalBody = "total-body"
}

enum WeeklyGoalMode: String, Codable, CaseIterable {
    case total
    case granular
}

/// The immutable, user-facing definition for one weekly goal revision.
struct WeeklyGoalDefinition: Codable, Hashable {
    let mode: WeeklyGoalMode
    let totalTarget: Int?
    let upperTarget: Int
    let lowerTarget: Int
    let totalBodyTarget: Int

    init(totalTarget: Int) throws {
        guard (1...14).contains(totalTarget) else { throw WeeklyGoalError.invalidTarget }
        self.mode = .total
        self.totalTarget = totalTarget
        self.upperTarget = 0
        self.lowerTarget = 0
        self.totalBodyTarget = 0
    }

    init(upperTarget: Int, lowerTarget: Int, totalBodyTarget: Int) throws {
        guard [upperTarget, lowerTarget, totalBodyTarget].allSatisfy({ (0...14).contains($0) }),
              upperTarget + lowerTarget + totalBodyTarget > 0 else {
            throw WeeklyGoalError.invalidTarget
        }
        self.mode = .granular
        self.totalTarget = nil
        self.upperTarget = upperTarget
        self.lowerTarget = lowerTarget
        self.totalBodyTarget = totalBodyTarget
    }

    var enabledTargets: [WorkoutBodyFocus: Int] {
        [.upperBody: upperTarget, .lowerBody: lowerTarget, .totalBody: totalBodyTarget]
            .filter { $0.value > 0 }
    }
}

enum WeeklyGoalError: Error, Equatable {
    case invalidTarget
    case invalidRevisionDate
    case invalidDefinitionData
}

/// Effective-dated local history. Keeping revisions (including disabled ones)
/// makes streaks reproducible after edits and across app launches.
@Model
final class WeeklyGoalRevision {
    var id: UUID = UUID()
    var effectiveFrom: Date = Date.now
    var enabled: Bool = true
    var definitionData: Data = Data()

    init(definition: WeeklyGoalDefinition, effectiveFrom: Date = Date.now) throws {
        self.id = UUID()
        self.effectiveFrom = effectiveFrom
        self.enabled = true
        self.definitionData = try JSONEncoder().encode(definition)
    }

    init(disabled effectiveFrom: Date = Date.now) {
        self.id = UUID()
        self.effectiveFrom = effectiveFrom
        self.enabled = false
        self.definitionData = Data()
    }

    var definition: WeeklyGoalDefinition? {
        guard enabled else { return nil }
        return try? JSONDecoder().decode(WeeklyGoalDefinition.self, from: definitionData)
    }
}

struct WeeklyGoalWeek: Identifiable {
    let id: Date
    let interval: DateInterval
    let enabled: Bool
    let definition: WeeklyGoalDefinition?
    let totalCount: Int
    let counts: [WorkoutBodyFocus: Int]
    let isComplete: Bool
    let isGraded: Bool
}

struct WeeklyGoalReport {
    let currentWeek: WeeklyGoalWeek
    let weeks: [WeeklyGoalWeek]
    let currentStreak: Int
    let bestStreak: Int
}

/// Pure evaluator. Callers can pass freshly fetched logs/revisions after every
/// mutation; no counters become stale and tests do not depend on wall-clock time.
struct WeeklyGoalEngine {
    var calendar: Calendar
    var now: Date

    init(calendar: Calendar = WeeklyGoalEngine.defaultCalendar, now: Date = .now) {
        var calendar = calendar
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 1
        self.calendar = calendar
        self.now = now
    }

    static var defaultCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }

    @MainActor
    func report(logs: [WorkoutLog], revisions: [WeeklyGoalRevision], catalog: CatalogStore? = nil) -> WeeklyGoalReport {
        let currentStart = weekStart(containing: now)
        let firstStart = revisions.map { weekStart(containing: $0.effectiveFrom) }.min() ?? currentStart
        var starts: [Date] = []
        var cursor = firstStart
        while cursor <= currentStart {
            starts.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 7, to: cursor) else { break }
            cursor = next
        }
        let weeks = starts.map { evaluate(start: $0, logs: logs, revisions: revisions, catalog: catalog) }
        let current = weeks.last ?? evaluate(start: currentStart, logs: logs, revisions: revisions, catalog: catalog)

        var currentStreak = 0
        if current.enabled {
            let closedOrCurrent = weeks.reversed()
            for week in closedOrCurrent {
                if week.id == current.id && !week.isComplete { continue }
                guard week.isComplete else { break }
                currentStreak += 1
            }
        }

        var best = 0
        var run = 0
        for week in weeks {
            if week.isComplete { run += 1; best = max(best, run) }
            else { run = 0 }
        }
        return WeeklyGoalReport(currentWeek: current, weeks: weeks,
                                currentStreak: currentStreak, bestStreak: best)
    }

    func weekStart(containing date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    @MainActor
    private func evaluate(start: Date, logs: [WorkoutLog], revisions: [WeeklyGoalRevision], catalog: CatalogStore?) -> WeeklyGoalWeek {
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start.addingTimeInterval(7 * 24 * 60 * 60)
        let interval = DateInterval(start: start, end: end)
        // The last revision before week close is the definition that week closed
        // under. For the current week, this also makes edits apply immediately.
        let revision = revisions.filter { $0.effectiveFrom < interval.end }
            .sorted { $0.effectiveFrom == $1.effectiveFrom ? $0.id.uuidString < $1.id.uuidString : $0.effectiveFrom < $1.effectiveFrom }
            .last
        let definition = revision?.definition
        let enabled = revision?.enabled == true
        let weekLogs = logs.filter { interval.contains($0.performedAt) }
        var counts: [WorkoutBodyFocus: Int] = [:]
        var total = 0
        for log in weekLogs {
            let focus = log.bodyFocus ?? catalog?.bodyFocus(for: log.workoutId)
            if let focus { counts[focus, default: 0] += 1 }
            if definition?.mode == .total { total += 1 }
        }
        let complete: Bool
        switch definition?.mode {
        case .total: complete = total >= (definition?.totalTarget ?? Int.max)
        case .granular:
            complete = definition?.enabledTargets.allSatisfy { counts[$0.key, default: 0] >= $0.value } == true
        case nil: complete = false
        }
        return WeeklyGoalWeek(id: start, interval: interval, enabled: enabled,
                              definition: definition, totalCount: total, counts: counts,
                              isComplete: enabled && definition != nil && complete,
                              isGraded: enabled && definition != nil)
    }
}
