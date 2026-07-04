import XCTest
@testable import GRYPD

@MainActor
final class CatalogAliasTests: XCTestCase {
    func testCatalogLookupResolvesFallbackAliasToCanonicalWorkout() {
        let workout = workout(id: "1890000000", aliases: ["seatable-row-1"], title: "Strength with Kim")
        let catalog = CatalogStore(workouts: [workout])

        XCTAssertEqual(catalog.workout(id: "seatable-row-1")?.id, "1890000000")
        XCTAssertEqual(catalog.canonicalWorkoutId(for: "seatable-row-1"), "1890000000")
        XCTAssertTrue(catalog.log(WorkoutLog(workoutId: "seatable-row-1"), belongsTo: workout))
    }

    func testLastDoneUsesCanonicalIdForAliasLogs() {
        let old = WorkoutLog(workoutId: "seatable-row-1", performedAt: Date(timeIntervalSince1970: 100))
        let newer = WorkoutLog(workoutId: "1890000000", performedAt: Date(timeIntervalSince1970: 200))
        let unrelated = WorkoutLog(workoutId: "missing-row", performedAt: Date(timeIntervalSince1970: 300))
        let catalog = CatalogStore(workouts: [
            workout(id: "1890000000", aliases: ["seatable-row-1"], title: "Strength with Kim")
        ])

        let lastDone = LogHistory.lastDoneByWorkout([old, newer, unrelated], catalog: catalog)

        XCTAssertEqual(lastDone.keys.sorted(), ["1890000000"])
        XCTAssertEqual(lastDone["1890000000"], newer.performedAt)
    }

    func testProgressionPointsUseCanonicalWorkoutForAliasLogs() {
        let log = WorkoutLog(workoutId: "seatable-row-1", performedAt: Date(timeIntervalSince1970: 100))
        let entry = MoveEntry(moveSlug: "squat", label: "Squat", weightValue: 40, weightUnit: .lb)
        entry.log = log
        log.moveEntries.append(entry)
        let catalog = CatalogStore(workouts: [
            workout(id: "1890000000", aliases: ["seatable-row-1"], title: "Strength with Kim")
        ])

        let points = ProgressionStats.exercisePoints(logs: [log], moveSlug: "squat", catalog: catalog)

        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].workoutId, "1890000000")
        XCTAssertEqual(points[0].workoutTitle, "Strength with Kim")
    }

    func testWorkoutDecodesAliasesFromCatalogJSON() throws {
        let data = """
        {
          "id": "1890000000",
          "aliases": ["seatable-row-1"],
          "discipline": "strength",
          "title": "Strength with Kim",
          "trainer": "kim",
          "durationMinutes": 20,
          "episode": 12,
          "appleUrl": "https://fitness.apple.com/us/workout/strength-with-kim/1890000000",
          "description": "Test",
          "releaseDate": "2026-06-29",
          "facets": {
            "bodyFocus": "total-body",
            "muscleGroups": ["glutes"],
            "equipment": ["dumbbells"],
            "dumbbells": ["2-medium"]
          },
          "moves": ["squat"]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(Workout.self, from: data)

        XCTAssertEqual(decoded.id, "1890000000")
        XCTAssertEqual(decoded.aliases, ["seatable-row-1"])
        XCTAssertEqual(decoded.summary, "Test")
    }
}

private func workout(id: String, aliases: [String]? = nil, title: String) -> Workout {
    Workout(
        id: id,
        aliases: aliases,
        discipline: "strength",
        title: title,
        trainer: "kim",
        durationMinutes: 20,
        episode: 12,
        appleUrl: "https://fitness.apple.com/us/workout/strength-with-kim/\(id)",
        summary: nil,
        releaseDate: "2026-06-29",
        facets: Facets(
            bodyFocus: "total-body",
            muscleGroups: ["glutes"],
            equipment: ["dumbbells"],
            dumbbells: ["2-medium"]
        ),
        moves: ["squat"],
        moveSequence: nil,
        coachNotes: nil
    )
}
