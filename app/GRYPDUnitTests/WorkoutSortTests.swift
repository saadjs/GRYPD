import XCTest
@testable import GRYPD

final class WorkoutSortTests: XCTestCase {
    func testNewestFirstSortsReleaseDatesDescending() {
        let workouts = [
            workout(id: "1854786321", title: "Older ID", releaseDate: "2025-12-22"),
            workout(id: "1854786231", title: "Newer Release", releaseDate: "2025-12-29"),
            workout(id: "1854786400", title: "Middle Release", releaseDate: "2025-12-25")
        ]

        XCTAssertEqual(workouts.sorted(by: Workout.newestFirst).map(\.id), ["1854786231", "1854786400", "1854786321"])
    }

    func testNewestFirstFallsBackToNumericAppleIDsDescending() {
        let workouts = [
            workout(id: "200", title: "Middle"),
            workout(id: "300", title: "Newest"),
            workout(id: "100", title: "Oldest")
        ]

        XCTAssertEqual(workouts.sorted(by: Workout.newestFirst).map(\.id), ["300", "200", "100"])
    }

    func testNewestFirstSortsMissingReleaseDatesAfterDatedWorkouts() {
        let workouts = [
            workout(id: "300", title: "Undated"),
            workout(id: "100", title: "Dated", releaseDate: "2025-12-29")
        ]

        XCTAssertEqual(workouts.sorted(by: Workout.newestFirst).map(\.title), ["Dated", "Undated"])
    }

    func testNewestFirstFallsBackToTitleForNonNumericIDs() {
        let workouts = [
            workout(id: "beta", title: "Bravo"),
            workout(id: "alpha", title: "Alpha")
        ]

        XCTAssertEqual(workouts.sorted(by: Workout.newestFirst).map(\.title), ["Alpha", "Bravo"])
    }
}

private func workout(id: String, title: String, releaseDate: String? = nil) -> Workout {
    Workout(
        id: id,
        discipline: "strength",
        title: title,
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
            dumbbells: nil
        ),
        moves: [],
        moveSequence: nil,
        coachNotes: nil
    )
}
