import XCTest
@testable import GRYPD

final class WorkoutMonthTests: XCTestCase {
    /// Regression: a workout released on the first day of a month must land in
    /// that month's bucket AND carry that month's label. The bucket boundary is
    /// a UTC month-start, so the label must be formatted in UTC — otherwise a
    /// 2026-06-01T00:00Z boundary renders as "MAY 2026" anywhere behind UTC.
    func testMonthLabelMatchesUTCBucketBoundary() {
        let months = [
            workout(id: "300", releaseDate: "2026-06-29"),
            workout(id: "200", releaseDate: "2026-06-01"),
            workout(id: "100", releaseDate: "2026-05-15")
        ].byMonth()

        XCTAssertEqual(months.map(\.label), ["JUNE 2026", "MAY 2026"])
        XCTAssertEqual(months.first?.workouts.map(\.id), ["300", "200"])
    }

    func testMonthsSortedNewestFirst() {
        let months = [
            workout(id: "a", releaseDate: "2026-05-10"),
            workout(id: "b", releaseDate: "2026-06-10"),
            workout(id: "c", releaseDate: "2026-04-10")
        ].byMonth()

        XCTAssertEqual(months.map(\.label), ["JUNE 2026", "MAY 2026", "APRIL 2026"])
    }
}

private func workout(id: String, releaseDate: String?) -> Workout {
    Workout(
        id: id,
        discipline: "strength",
        title: id,
        trainer: "amir",
        durationMinutes: 20,
        episode: nil,
        appleUrl: "https://fitness.apple.com/us/workout/\(id)",
        summary: nil,
        releaseDate: releaseDate,
        facets: Facets(
            bodyFocus: "total-body",
            muscleGroups: [],
            equipment: [],
            dumbbells: nil,
            dumbbellLoad: nil
        ),
        moves: [],
        moveSequence: nil,
        coachNotes: nil
    )
}
