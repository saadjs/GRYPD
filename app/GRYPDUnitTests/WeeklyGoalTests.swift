import XCTest
@testable import GRYPD

@MainActor
final class WeeklyGoalTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 1
        return c
    }

    private var monday: Date { calendar.date(from: DateComponents(year: 2026, month: 7, day: 6, hour: 12))! }
    private func day(_ offset: Int, hour: Int = 12) -> Date {
        calendar.date(byAdding: .day, value: offset, to: monday)!.addingTimeInterval(TimeInterval(hour - 12) * 3600)
    }
    private func revision(_ definition: WeeklyGoalDefinition, at date: Date) throws -> WeeklyGoalRevision {
        try WeeklyGoalRevision(definition: definition, effectiveFrom: date)
    }

    private func weeklyGoalTestWorkout(id: String, bodyFocus: String) -> Workout {
        Workout(id: id, aliases: nil, discipline: "strength", title: "Test Workout",
                trainer: "test", durationMinutes: 20, episode: nil, appleUrl: nil,
                summary: nil, releaseDate: nil,
                facets: Facets(bodyFocus: bodyFocus, muscleGroups: [], equipment: [],
                               dumbbells: nil, dumbbellLoad: nil),
                moves: [], moveSequence: nil, coachNotes: nil)
    }

    func testValidationEnforcesRangesAndAtLeastOneGranularTarget() throws {
        XCTAssertThrowsError(try WeeklyGoalDefinition(totalTarget: 0))
        XCTAssertThrowsError(try WeeklyGoalDefinition(totalTarget: 15))
        XCTAssertThrowsError(try WeeklyGoalDefinition(upperTarget: 0, lowerTarget: 0, totalBodyTarget: 0))
        XCTAssertThrowsError(try WeeklyGoalDefinition(upperTarget: 15, lowerTarget: 0, totalBodyTarget: 0))
        XCTAssertNoThrow(try WeeklyGoalDefinition(upperTarget: 0, lowerTarget: 1, totalBodyTarget: 14))
    }

    func testTotalCountsEveryLogIncludingRepeatedWorkoutsAndExcess() throws {
        let goal = try WeeklyGoalDefinition(totalTarget: 2)
        let logs = [WorkoutLog(workoutId: "same", performedAt: day(0)),
                    WorkoutLog(workoutId: "same", performedAt: day(1)),
                    WorkoutLog(workoutId: "unknown", performedAt: day(2))]
        let report = WeeklyGoalEngine(calendar: calendar, now: day(3)).report(
            logs: logs, revisions: [try revision(goal, at: day(-1))])
        XCTAssertEqual(report.currentWeek.totalCount, 3)
        XCTAssertTrue(report.currentWeek.isComplete)
    }

    func testGranularUsesSnapshotAndCatalogFallbackButUnknownLegacyIsNotCounted() throws {
        let goal = try WeeklyGoalDefinition(upperTarget: 1, lowerTarget: 1, totalBodyTarget: 1)
        let snap = WorkoutLog(workoutId: "old", performedAt: day(0), bodyFocus: .upperBody)
        let legacy = WorkoutLog(workoutId: "unknown", performedAt: day(1))
        let catalogWorkout = weeklyGoalTestWorkout(id: "lower", bodyFocus: "lower-body")
        let catalog = CatalogStore(workouts: [catalogWorkout])
        let catalogLog = WorkoutLog(workoutId: "lower", performedAt: day(2))
        let totalBody = WorkoutLog(workoutId: "total", performedAt: day(3), bodyFocus: .totalBody)
        let report = WeeklyGoalEngine(calendar: calendar, now: day(4)).report(
            logs: [snap, legacy, catalogLog, totalBody],
            revisions: [try revision(goal, at: day(-1))], catalog: catalog)
        XCTAssertEqual(report.currentWeek.counts[WorkoutBodyFocus.upperBody], 1)
        XCTAssertEqual(report.currentWeek.counts[WorkoutBodyFocus.lowerBody], 1)
        XCTAssertEqual(report.currentWeek.counts[WorkoutBodyFocus.totalBody], 1)
        XCTAssertTrue(report.currentWeek.isComplete)
    }

    func testEnablingMidweekIncludesEarlierLogsAndPreActivationWeekIsUngraded() throws {
        let goal = try WeeklyGoalDefinition(totalTarget: 2)
        let report = WeeklyGoalEngine(calendar: calendar, now: day(2)).report(
            logs: [WorkoutLog(workoutId: "a", performedAt: day(0)), WorkoutLog(workoutId: "b", performedAt: day(1))],
            revisions: [try revision(goal, at: day(1))])
        XCTAssertTrue(report.currentWeek.isComplete)
        XCTAssertEqual(report.weeks.count, 1)
        let before = WeeklyGoalEngine(calendar: calendar, now: day(-2)).report(logs: [], revisions: [try revision(goal, at: day(1))])
        XCTAssertFalse(before.currentWeek.isGraded)
    }

    func testCurrentIncompleteWeekDoesNotBreakStreakAndClosedIncompleteDoes() throws {
        let goal = try WeeklyGoalDefinition(totalTarget: 1)
        let logs = [WorkoutLog(workoutId: "a", performedAt: day(-7))]
        let report = WeeklyGoalEngine(calendar: calendar, now: day(1)).report(
            logs: logs, revisions: [try revision(goal, at: day(-14))])
        XCTAssertEqual(report.currentStreak, 1)
        XCTAssertEqual(report.bestStreak, 1)
    }

    func testDisableBreaksRunAndReenableSameWeekResumesWithCurrentDefinition() throws {
        let goal = try WeeklyGoalDefinition(totalTarget: 1)
        let disabled = WeeklyGoalRevision(disabled: day(1))
        let reenabled = try revision(goal, at: day(2))
        let report = WeeklyGoalEngine(calendar: calendar, now: day(3)).report(
            logs: [WorkoutLog(workoutId: "a", performedAt: day(0))],
            revisions: [try revision(goal, at: day(-14)), disabled, reenabled])
        XCTAssertTrue(report.currentWeek.isComplete)
        XCTAssertEqual(report.bestStreak, 1)
        XCTAssertEqual(report.currentStreak, 1)
    }

    func testDisabledCurrentWeekImmediatelyZerosCurrentStreakButPreservesBest() throws {
        let goal = try WeeklyGoalDefinition(totalTarget: 1)
        let report = WeeklyGoalEngine(calendar: calendar, now: day(3)).report(
            logs: [WorkoutLog(workoutId: "a", performedAt: day(-7)),
                   WorkoutLog(workoutId: "b", performedAt: day(0))],
            revisions: [try revision(goal, at: day(-14)), WeeklyGoalRevision(disabled: day(1))])
        XCTAssertFalse(report.currentWeek.enabled)
        XCTAssertEqual(report.currentStreak, 0)
        XCTAssertEqual(report.bestStreak, 1)
    }

    func testWeekIntervalUsesCalendarDaysAcrossDST() throws {
        var dstCalendar = calendar
        dstCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        let dstNow = dstCalendar.date(from: DateComponents(year: 2026, month: 3, day: 11, hour: 12))!
        let goal = try WeeklyGoalDefinition(totalTarget: 1)
        let report = WeeklyGoalEngine(calendar: dstCalendar, now: dstNow).report(
            logs: [WorkoutLog(workoutId: "a", performedAt: dstNow)],
            revisions: [try revision(goal, at: dstNow.addingTimeInterval(-86400))])
        XCTAssertEqual(dstCalendar.dateComponents([.day], from: report.currentWeek.interval.start,
                                                   to: report.currentWeek.interval.end).day, 7)
        XCTAssertTrue(report.currentWeek.isComplete)
    }

    func testBackdatingAndDeletionRecalculateAchievement() throws {
        let goal = try WeeklyGoalDefinition(totalTarget: 2)
        let first = WorkoutLog(workoutId: "a", performedAt: day(0))
        let second = WorkoutLog(workoutId: "b", performedAt: day(1))
        let engine = WeeklyGoalEngine(calendar: calendar, now: day(2))
        let revision = try revision(goal, at: day(-1))
        XCTAssertTrue(engine.report(logs: [first, second], revisions: [revision]).currentWeek.isComplete)
        XCTAssertFalse(engine.report(logs: [first], revisions: [revision]).currentWeek.isComplete)
        first.performedAt = day(-7)
        XCTAssertFalse(engine.report(logs: [first, second], revisions: [revision]).currentWeek.isComplete)
    }

    func testClosedWeekKeepsDefinitionThatWasEffectiveWhenItClosed() throws {
        let one = try WeeklyGoalDefinition(totalTarget: 1)
        let three = try WeeklyGoalDefinition(totalTarget: 3)
        let report = WeeklyGoalEngine(calendar: calendar, now: day(8)).report(
            logs: [WorkoutLog(workoutId: "a", performedAt: day(0))],
            revisions: [try revision(one, at: day(-14)), try revision(three, at: day(7))])
        let prior = report.weeks[report.weeks.count - 2]
        XCTAssertEqual(prior.definition?.totalTarget, 1)
        XCTAssertTrue(prior.isComplete)
    }
}
