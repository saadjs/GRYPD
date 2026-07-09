import XCTest
@testable import GRYPD

@MainActor
final class ProgressionStatsTests: XCTestCase {

    // MARK: - Weight normalization (top-set weight, display unit)

    func testExercisePointsNormalizeMixedWeightUnitsToDisplayUnit() throws {
        let logs = [
            weightedLog(id: "workout-a", at: 100, slug: "deadlift", weight: 40, unit: .kg),
            weightedLog(id: "workout-b", at: 200, slug: "deadlift", weight: 50, unit: .lb)
        ]
        let catalog = CatalogStore()

        let points = ProgressionStats.exercisePoints(logs: logs,
                                                     moveSlug: "deadlift",
                                                     catalog: catalog,
                                                     displayUnit: .lb)

        XCTAssertEqual(points.map(\.unit), [.lb, .lb])
        XCTAssertEqual(points[0].weight, 88.184904872, accuracy: 0.000001)
        XCTAssertEqual(points[1].weight, 50, accuracy: 0.000001)
        XCTAssertEqual(points.first?.kind, .weighted)
    }

    func testExercisePointsCanNormalizePoundsToKilograms() {
        let logs = [weightedLog(id: "workout-a", at: 100, slug: "squat", weight: 55, unit: .lb)]
        let catalog = CatalogStore()

        let points = ProgressionStats.exercisePoints(logs: logs,
                                                     moveSlug: "squat",
                                                     catalog: catalog,
                                                     displayUnit: .kg)

        XCTAssertEqual(points.map(\.unit), [.kg])
        XCTAssertEqual(points.first?.weight ?? 0, 24.94758036, accuracy: 0.000001)
    }

    // MARK: - Epley estimated 1RM

    func testEpleyBaseline() {
        XCTAssertEqual(MetricKind.estimatedOneRepMax(weight: 100, reps: 10),
                       133.3333, accuracy: 0.001)
        // 1 rep is just the weight itself.
        XCTAssertEqual(MetricKind.estimatedOneRepMax(weight: 100, reps: 1),
                       103.3333, accuracy: 0.001)
    }

    func testEpleyMissingRepsCountAsOne() {
        // Logging a weight with no reps shouldn't drop or zero the estimate — it
        // floors to a single rep (i.e. the weight).
        XCTAssertEqual(MetricKind.estimatedOneRepMax(weight: 100, reps: nil),
                       103.3333, accuracy: 0.001)
        XCTAssertEqual(MetricKind.estimatedOneRepMax(weight: 100, reps: 0),
                       103.3333, accuracy: 0.001)
    }

    func testEpleyClampsRepsAtTwelve() {
        let atTwelve = MetricKind.estimatedOneRepMax(weight: 100, reps: 12)
        let above = MetricKind.estimatedOneRepMax(weight: 100, reps: 30)
        XCTAssertEqual(atTwelve, 140, accuracy: 0.001)
        XCTAssertEqual(above, 140, accuracy: 0.001, "reps past 12 must not inflate the estimate")
    }

    func testEpleyAddsRepsInReserveToCompletedReps() {
        XCTAssertEqual(
            MetricKind.estimatedOneRepMax(weight: 100, reps: 8, repsInReserve: 2),
            133.3333,
            accuracy: 0.001
        )
    }

    func testEffortAdjustedEpleyClampsCombinedRepsAtTwelve() {
        XCTAssertEqual(
            MetricKind.estimatedOneRepMax(weight: 100, reps: 10, repsInReserve: 4),
            140,
            accuracy: 0.001
        )
    }

    func testWeightedIntensityUsesSavedRepsInReserve() {
        let set = SetEntry(order: 0, weightValue: 100, weightUnit: .lb,
                           reps: 8, repsInReserve: 2)

        XCTAssertEqual(MetricKind.weighted.intensity(of: set, displayUnit: .lb),
                       133.3333, accuracy: 0.001)
    }

    func testWeightedPeakUsesRatedLastSetInsteadOfUnratedEarlierSets() {
        let unrated = SetEntry(order: 0, weightValue: 100, weightUnit: .lb, reps: 12)
        let ratedLast = SetEntry(order: 1, weightValue: 80, weightUnit: .lb,
                                 reps: 8, repsInReserve: 2)

        XCTAssertIdentical(
            MetricKind.weighted.peakSet(in: [unrated, ratedLast], displayUnit: .lb),
            ratedLast
        )
    }

    // MARK: - Per-move-type classification (from the latest session)

    func testMoveClassifiedByLatestSessionTopSet() {
        // Earlier session was pure bodyweight; the latest added load. The move now
        // reads as weighted, and the earlier point's est. max is ~0 (no load then).
        let early = MoveEntry(moveSlug: "push-up", label: "Push-Up")
        early.sets = [SetEntry(order: 0, reps: 20)]
        let late = MoveEntry(moveSlug: "push-up", label: "Push-Up",
                             weightValue: 25, weightUnit: .lb, reps: 8)
        let points = ProgressionStats.exercisePoints(
            logs: [log(id: "a", at: 100, entry: early),
                   log(id: "b", at: 200, entry: late)],
            moveSlug: "push-up", catalog: CatalogStore(), displayUnit: .lb)

        XCTAssertEqual(points.map(\.kind), [.weighted, .weighted])
        XCTAssertEqual(points[0].intensity, 0, accuracy: 0.001)
        XCTAssertEqual(points[1].intensity, 25 * (1 + 8.0 / 30), accuracy: 0.001)
    }

    func testBodyweightMoveIntensityIsBestSetReps() {
        let entry = MoveEntry(moveSlug: "pull-up", label: "Pull-Up")
        entry.sets = [SetEntry(order: 0, reps: 8), SetEntry(order: 1, reps: 12)]
        let points = ProgressionStats.exercisePoints(
            logs: [log(id: "a", at: 100, entry: entry)],
            moveSlug: "pull-up", catalog: CatalogStore())

        XCTAssertEqual(points.first?.kind, .bodyweight)
        XCTAssertEqual(points.first?.intensity, 12)
    }

    func testTimedMoveIntensityIsLongestHold() {
        let entry = MoveEntry(moveSlug: "plank", label: "Plank")
        entry.sets = [SetEntry(order: 0, seconds: 30), SetEntry(order: 1, seconds: 75)]
        let points = ProgressionStats.exercisePoints(
            logs: [log(id: "a", at: 100, entry: entry)],
            moveSlug: "plank", catalog: CatalogStore())

        XCTAssertEqual(points.first?.kind, .timed)
        XCTAssertEqual(points.first?.intensity, 75)
    }

    // MARK: - Volume

    func testWeightedVolumeIsTonnageAcrossSets() {
        let entry = MoveEntry(moveSlug: "row", label: "Row")
        entry.sets = [
            SetEntry(order: 0, weightValue: 40, weightUnit: .lb, reps: 8),
            SetEntry(order: 1, weightValue: 50, weightUnit: .lb, reps: 6)
        ]
        let points = ProgressionStats.exercisePoints(
            logs: [log(id: "a", at: 100, entry: entry)],
            moveSlug: "row", catalog: CatalogStore(), displayUnit: .lb)

        XCTAssertEqual(points.first?.volume, 40 * 8 + 50 * 6) // 620
    }

    func testWeightedIntensityUsesBestEpleyNotHeaviestSet() {
        // A top single at 110×1 and a backoff set at 100×12 in the same session.
        // `topSet` ranks by raw weight and would pick the 110 single (est ≈ 114),
        // but the 100×12 backoff estimates a larger one-rep max (≈ 140) and must be
        // what the intensity/PR line charts. The point's reps follow that set too.
        let entry = MoveEntry(moveSlug: "bench", label: "Bench Press")
        entry.sets = [
            SetEntry(order: 0, weightValue: 110, weightUnit: .lb, reps: 1),
            SetEntry(order: 1, weightValue: 100, weightUnit: .lb, reps: 12)
        ]
        let points = ProgressionStats.exercisePoints(
            logs: [log(id: "a", at: 100, entry: entry)],
            moveSlug: "bench", catalog: CatalogStore(), displayUnit: .lb)

        XCTAssertEqual(points.first?.intensity ?? 0, 100 * (1 + 12.0 / 30), accuracy: 0.001)
        XCTAssertEqual(points.first?.reps, 12)
        XCTAssertEqual(points.first?.weight ?? 0, 100, accuracy: 0.001)
    }

    func testWeightedVolumeCountsMissingRepsAsOne() {
        // A weight-only set contributes its weight once rather than vanishing to 0.
        let entry = MoveEntry(moveSlug: "row", label: "Row")
        entry.sets = [SetEntry(order: 0, weightValue: 45, weightUnit: .lb, reps: nil)]
        let points = ProgressionStats.exercisePoints(
            logs: [log(id: "a", at: 100, entry: entry)],
            moveSlug: "row", catalog: CatalogStore(), displayUnit: .lb)

        XCTAssertEqual(points.first?.volume, 45)
    }

    func testBodyweightAndTimedVolumeSumSets() {
        let reps = MoveEntry(moveSlug: "pull-up", label: "Pull-Up")
        reps.sets = [SetEntry(order: 0, reps: 8), SetEntry(order: 1, reps: 12)]
        let repPoints = ProgressionStats.exercisePoints(
            logs: [log(id: "a", at: 100, entry: reps)],
            moveSlug: "pull-up", catalog: CatalogStore())
        XCTAssertEqual(repPoints.first?.volume, 20)

        let timed = MoveEntry(moveSlug: "plank", label: "Plank")
        timed.sets = [SetEntry(order: 0, seconds: 30), SetEntry(order: 1, seconds: 45)]
        let timedPoints = ProgressionStats.exercisePoints(
            logs: [log(id: "b", at: 100, entry: timed)],
            moveSlug: "plank", catalog: CatalogStore())
        XCTAssertEqual(timedPoints.first?.volume, 75)
    }

    // MARK: - Daily series (same-day multi-session collapse)

    func testDailySeriesSumsVolumeButMaxesIntensityAcrossSameDaySessions() {
        // Same move logged in two separate workouts on one calendar day.
        let sessionA = MoveEntry(moveSlug: "bench", label: "Bench Press")
        sessionA.sets = [SetEntry(order: 0, weightValue: 40, weightUnit: .lb, reps: 8)] // vol 320
        let sessionB = MoveEntry(moveSlug: "bench", label: "Bench Press")
        sessionB.sets = [SetEntry(order: 0, weightValue: 50, weightUnit: .lb, reps: 6)] // vol 300
        // Two timestamps a few hours apart on the same day (well clear of midnight).
        let noon: TimeInterval = 12 * 3600
        let points = ProgressionStats.exercisePoints(
            logs: [log(id: "a", at: noon, entry: sessionA),
                   log(id: "b", at: noon + 3 * 3600, entry: sessionB)],
            moveSlug: "bench", catalog: CatalogStore(), displayUnit: .lb)
        XCTAssertEqual(points.count, 2)

        let volume = ProgressionStats.dailySeries(points, mode: .volume)
        XCTAssertEqual(volume.count, 1)
        XCTAssertEqual(volume.first?.volume ?? 0, 620, accuracy: 0.001) // 320 + 300, not max(320,300)

        let intensity = ProgressionStats.dailySeries(points, mode: .intensity)
        XCTAssertEqual(intensity.count, 1)
        // Best est. max of the day: 50x6 (60) beats 40x8 (~50.7), not summed.
        XCTAssertEqual(intensity.first?.intensity ?? 0, 50 * (1 + 6.0 / 30), accuracy: 0.001)
    }

    func testSummaryVolumeStatsUseDailyTotalsNotSingleSessions() throws {
        // Two bench sessions on one day (vol 320 and 300) plus a lighter day earlier
        // (vol 200). The hero's Best/Latest/Start in Volume mode must track the chart's
        // summed daily bars (620 for the two-session day), not any single session's max.
        let early = MoveEntry(moveSlug: "bench", label: "Bench Press")
        early.sets = [SetEntry(order: 0, weightValue: 25, weightUnit: .lb, reps: 8)] // vol 200
        let sessionA = MoveEntry(moveSlug: "bench", label: "Bench Press")
        sessionA.sets = [SetEntry(order: 0, weightValue: 40, weightUnit: .lb, reps: 8)] // vol 320
        let sessionB = MoveEntry(moveSlug: "bench", label: "Bench Press")
        sessionB.sets = [SetEntry(order: 0, weightValue: 50, weightUnit: .lb, reps: 6)] // vol 300
        let dayOne: TimeInterval = 12 * 3600
        let dayTwo: TimeInterval = dayOne + 10 * 86_400
        let summaries = ProgressionStats.exerciseSummaries(
            logs: [log(id: "e", at: dayOne, entry: early),
                   log(id: "a", at: dayTwo, entry: sessionA),
                   log(id: "b", at: dayTwo + 3 * 3600, entry: sessionB)],
            catalog: CatalogStore(), displayUnit: .lb)
        let summary = try XCTUnwrap(summaries.first)

        // Best day = 320 + 300, not the max single session (320).
        XCTAssertEqual(summary.best(.volume).value(for: .volume), 620, accuracy: 0.001)
        // Latest bar (most recent day) is the two-session total, headline follows it.
        XCTAssertEqual(summary.headlineValue(.volume), "620")
        // Delta = latest day (620) − first day (200).
        XCTAssertEqual(summary.delta(.volume), 420, accuracy: 0.001)
    }

    // MARK: - Personal records

    func testSingleEntryMoveIsNotAPR() throws {
        let logs = [weightedLog(id: "a", at: 100, slug: "squat", weight: 40, unit: .lb)]
        let summaries = ProgressionStats.exerciseSummaries(
            logs: logs, catalog: CatalogStore(), displayUnit: .lb)
        XCTAssertEqual(ProgressionStats.prCount(summaries, allTimePoints: allTimePoints(logs)), 0)
    }

    func testLatestSessionBeatingPriorBestIsAPR() throws {
        let logs = [weightedLog(id: "a", at: 100, slug: "squat", weight: 40, unit: .lb),
                    weightedLog(id: "b", at: 200, slug: "squat", weight: 55, unit: .lb)]
        let summaries = ProgressionStats.exerciseSummaries(
            logs: logs, catalog: CatalogStore(), displayUnit: .lb)
        XCTAssertEqual(ProgressionStats.prCount(summaries, allTimePoints: allTimePoints(logs)), 1)
    }

    func testLatestSessionNotBeatingPriorBestIsNotAPR() throws {
        let logs = [weightedLog(id: "a", at: 100, slug: "squat", weight: 55, unit: .lb),
                    weightedLog(id: "b", at: 200, slug: "squat", weight: 40, unit: .lb)]
        let summaries = ProgressionStats.exerciseSummaries(
            logs: logs, catalog: CatalogStore(), displayUnit: .lb)
        XCTAssertEqual(ProgressionStats.prCount(summaries, allTimePoints: allTimePoints(logs)), 0)
    }

    func testRangeBestBeatenByOutOfRangeSessionIsNotAPR() throws {
        // A heavier squat 8 months ago, then a lighter one last month. Viewing a 6M
        // window, the recent session is the best *in range* but not an all-time PR —
        // the out-of-range 225 already beat it, so the tile must not count it.
        let old = weightedLog(id: "old", at: 0, slug: "squat", weight: 225, unit: .lb)
        old.performedAt = Date(timeIntervalSinceNow: -240 * 86_400)
        let recent = weightedLog(id: "recent", at: 0, slug: "squat", weight: 205, unit: .lb)
        recent.performedAt = Date(timeIntervalSinceNow: -30 * 86_400)

        let inRange = ProgressionStats.logs([old, recent], in: .sixMonths)
        XCTAssertEqual(inRange.count, 1, "the 225 session should fall outside 6M")
        let summaries = ProgressionStats.exerciseSummaries(
            logs: inRange, catalog: CatalogStore(), displayUnit: .lb)

        // Range-scoped, the recent 205 would look like a fresh PR; against all-time
        // history (which still holds the 225) it is not.
        XCTAssertEqual(ProgressionStats.prCount(summaries, allTimePoints: allTimePoints([old, recent])), 0)
    }

    // MARK: - Ordering

    func testSummariesSortMostRecentlyPerformedFirst() {
        let summaries = ProgressionStats.exerciseSummaries(
            logs: [weightedLog(id: "a", at: 100, slug: "squat", weight: 40, unit: .lb),
                   weightedLog(id: "b", at: 500, slug: "bench", weight: 60, unit: .lb)],
            catalog: CatalogStore(), displayUnit: .lb)

        XCTAssertEqual(summaries.map(\.moveSlug), ["bench", "squat"])
    }

    // MARK: - Existing behaviors preserved

    func testCustomExercisesAreIncludedInProgressionByNormalizedLabel() throws {
        let entry = MoveEntry(moveSlug: nil, label: "Suitcase Carry",
                              weightValue: 45, weightUnit: .lb, reps: 10)
        let summaries = ProgressionStats.exerciseSummaries(
            logs: [log(id: "a", at: 100, entry: entry)],
            catalog: CatalogStore(), displayUnit: .lb)
        let summary = try XCTUnwrap(summaries.first)

        XCTAssertEqual(summary.moveSlug, "custom:suitcase-carry")
        XCTAssertEqual(summary.title, "Suitcase Carry")
        XCTAssertEqual(summary.latest.reps, 10)
    }

    func testEditedCatalogExerciseLabelIsUsedInProgressionTitle() throws {
        let points = ProgressionStats.exercisePoints(
            logs: [weightedLog(id: "a", at: 100, slug: "squat", label: "Box Squat", weight: 40, unit: .lb)],
            moveSlug: "squat", catalog: CatalogStore(), displayUnit: .lb)
        XCTAssertEqual(points.first?.title, "Box Squat")
    }

    func testExercisePointsUseBestSetPerSession() {
        let entry = MoveEntry(moveSlug: "squat", label: "Squat")
        entry.sets = [
            SetEntry(order: 0, weightValue: 35, weightUnit: .lb, reps: 12),
            SetEntry(order: 1, weightValue: 45, weightUnit: .lb, reps: 8)
        ]
        let points = ProgressionStats.exercisePoints(
            logs: [log(id: "a", at: 100, entry: entry)],
            moveSlug: "squat", catalog: CatalogStore(), displayUnit: .lb)

        XCTAssertEqual(points.first?.weight, 45)
        XCTAssertEqual(points.first?.reps, 8)
    }
}

final class MoveEntryTopSetTests: XCTestCase {
    func testTopSetPrefersHighestWeightThenRepsThenSeconds() throws {
        let entry = MoveEntry(moveSlug: "squat", label: "Squat")
        entry.sets = [
            SetEntry(order: 0, weightValue: 20, weightUnit: .lb, reps: 12, seconds: 45),
            SetEntry(order: 1, weightValue: 25, weightUnit: .lb, reps: 6, seconds: 30),
            SetEntry(order: 2, weightValue: 25, weightUnit: .lb, reps: 8, seconds: 25)
        ]

        let top = try XCTUnwrap(entry.topSet)
        XCTAssertEqual(top.order, 2)
    }

    func testTopSetFallsBackToRepsAndThenSecondsForWeightlessSets() throws {
        let repsEntry = MoveEntry(moveSlug: "push-up", label: "Push-Up")
        repsEntry.sets = [
            SetEntry(order: 0, reps: 10, seconds: 30),
            SetEntry(order: 1, reps: 12, seconds: 20)
        ]

        XCTAssertEqual(try XCTUnwrap(repsEntry.topSet).order, 1)

        let timedEntry = MoveEntry(moveSlug: "plank", label: "Plank")
        timedEntry.sets = [
            SetEntry(order: 0, seconds: 30),
            SetEntry(order: 1, seconds: 45)
        ]

        XCTAssertEqual(try XCTUnwrap(timedEntry.topSet).order, 1)
    }
}

// MARK: - Builders

/// All-time points across the given logs — the unfiltered history `prCount` needs
/// to tell a true PR from a merely range-scoped best.
@MainActor
private func allTimePoints(_ logs: [WorkoutLog]) -> [ExerciseProgressPoint] {
    ProgressionStats.exercisePoints(logs: logs, catalog: CatalogStore(), displayUnit: .lb)
}

/// A log holding one move entry (with whatever sets the caller built).
private func log(id: String, at seconds: TimeInterval, entry: MoveEntry) -> WorkoutLog {
    let log = WorkoutLog(workoutId: id, performedAt: Date(timeIntervalSince1970: seconds))
    entry.log = log
    log.moveEntries.append(entry)
    return log
}

/// A log with a single weighted set — the common case for the weight/PR/sort tests.
private func weightedLog(id: String,
                         at seconds: TimeInterval,
                         slug: String,
                         label: String? = nil,
                         weight: Double,
                         unit: WeightUnit) -> WorkoutLog {
    let entry = MoveEntry(moveSlug: slug, label: label ?? slug,
                          weightValue: weight, weightUnit: unit, reps: 5)
    return log(id: id, at: seconds, entry: entry)
}
