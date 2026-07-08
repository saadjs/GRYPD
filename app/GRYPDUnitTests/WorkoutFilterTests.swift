import XCTest
@testable import GRYPD

final class WorkoutFilterTests: XCTestCase {
    private let tenMinuteTotal = workout(
        id: "ten-total",
        title: "Strength with Amir",
        trainer: "amir",
        duration: 10,
        bodyFocus: "total-body",
        muscleGroups: ["chest", "core"],
        equipment: ["dumbbells", "mat"]
    )

    private let elevenMinuteUpper = workout(
        id: "eleven-upper",
        title: "Strength with Sam",
        trainer: "sam",
        duration: 11,
        bodyFocus: "upper-body",
        muscleGroups: ["back", "shoulders"],
        equipment: ["dumbbells"]
    )

    private let twentyMinuteLower = workout(
        id: "twenty-lower",
        title: "Strength with Kim",
        trainer: "kim",
        duration: 20,
        bodyFocus: "lower-body",
        muscleGroups: ["glutes", "thighs"],
        equipment: ["mat"]
    )

    private let thirtyOneMinuteTotalBodyweight = workout(
        id: "thirtyone-total-bodyweight",
        title: "Strength with Gregg",
        trainer: "gregg",
        duration: 31,
        bodyFocus: "total-body",
        muscleGroups: ["core", "glutes"],
        equipment: ["no-equipment"]
    )

    func testEmptyFilterMatchesEveryWorkout() {
        let filter = WorkoutFilter()

        XCTAssertTrue(filter.matches(tenMinuteTotal))
        XCTAssertTrue(filter.matches(elevenMinuteUpper))
        XCTAssertTrue(filter.matches(twentyMinuteLower))
        XCTAssertTrue(filter.matches(thirtyOneMinuteTotalBodyweight))
    }

    func testDurationFilterUsesWorkoutBuckets() {
        var filter = WorkoutFilter()
        filter.durations = [10]

        XCTAssertTrue(filter.matches(tenMinuteTotal))
        XCTAssertTrue(filter.matches(elevenMinuteUpper))
        XCTAssertFalse(filter.matches(twentyMinuteLower))
        XCTAssertFalse(filter.matches(thirtyOneMinuteTotalBodyweight))

        XCTAssertEqual(elevenMinuteUpper.durationBucket, 10)
        XCTAssertEqual(elevenMinuteUpper.durationLabel, "10 min")
        XCTAssertEqual(thirtyOneMinuteTotalBodyweight.durationBucket, 30)
        XCTAssertEqual(thirtyOneMinuteTotalBodyweight.durationLabel, "30 min")
    }

    func testMultipleSelectionsWithinTheSameFacetAreOrFilters() {
        var filter = WorkoutFilter()
        filter.bodyFocus = ["upper-body", "lower-body"]

        XCTAssertFalse(filter.matches(tenMinuteTotal))
        XCTAssertTrue(filter.matches(elevenMinuteUpper))
        XCTAssertTrue(filter.matches(twentyMinuteLower))
        XCTAssertFalse(filter.matches(thirtyOneMinuteTotalBodyweight))

        filter = WorkoutFilter()
        filter.muscleGroups = ["chest", "glutes"]

        XCTAssertTrue(filter.matches(tenMinuteTotal))
        XCTAssertFalse(filter.matches(elevenMinuteUpper))
        XCTAssertTrue(filter.matches(twentyMinuteLower))
        XCTAssertTrue(filter.matches(thirtyOneMinuteTotalBodyweight))
    }

    func testDifferentFacetCategoriesCombineWithAnd() {
        var filter = WorkoutFilter()
        filter.durations = [10]
        filter.bodyFocus = ["upper-body"]
        filter.muscleGroups = ["shoulders"]
        filter.equipment = ["dumbbells"]

        XCTAssertFalse(filter.matches(tenMinuteTotal))
        XCTAssertTrue(filter.matches(elevenMinuteUpper))
        XCTAssertFalse(filter.matches(twentyMinuteLower))
        XCTAssertFalse(filter.matches(thirtyOneMinuteTotalBodyweight))
    }

    func testEquipmentFiltersMatchAnySelectedEquipment() {
        var filter = WorkoutFilter()
        filter.equipment = ["dumbbells", "no-equipment"]

        XCTAssertTrue(filter.matches(tenMinuteTotal))
        XCTAssertTrue(filter.matches(elevenMinuteUpper))
        XCTAssertFalse(filter.matches(twentyMinuteLower))
        XCTAssertTrue(filter.matches(thirtyOneMinuteTotalBodyweight))
    }

    func testDumbbellLoadFiltersRequireExactlySelectedWeightedBuckets() {
        let heavy = workout(id: "h", title: "T", trainer: "x", duration: 20,
                            bodyFocus: "total-body", muscleGroups: ["core"],
                            equipment: ["dumbbells"], dumbbellLoad: ["heavy"])
        let mediumHeavy = workout(id: "mh", title: "T", trainer: "x", duration: 20,
                                  bodyFocus: "total-body", muscleGroups: ["core"],
                                  equipment: ["dumbbells"], dumbbellLoad: ["medium", "heavy"])
        let lightHeavy = workout(id: "lh", title: "T", trainer: "x", duration: 20,
                                 bodyFocus: "total-body", muscleGroups: ["core"],
                                 equipment: ["dumbbells"], dumbbellLoad: ["light", "heavy"])
        let light = workout(id: "l", title: "T", trainer: "x", duration: 20,
                            bodyFocus: "total-body", muscleGroups: ["core"],
                            equipment: ["dumbbells"], dumbbellLoad: ["light"])
        let bodyweight = workout(id: "bw", title: "T", trainer: "x", duration: 20,
                                 bodyFocus: "total-body", muscleGroups: ["core"],
                                 equipment: ["no-equipment"], dumbbellLoad: ["bodyweight"])

        var filter = WorkoutFilter()
        filter.dumbbellLoad = ["heavy"]
        XCTAssertTrue(filter.matches(heavy))
        XCTAssertFalse(filter.matches(mediumHeavy))
        XCTAssertFalse(filter.matches(lightHeavy))
        XCTAssertFalse(filter.matches(light))
        XCTAssertTrue(filter.matches(bodyweight))

        filter.dumbbellLoad = ["medium", "heavy"]
        XCTAssertFalse(filter.matches(heavy))
        XCTAssertTrue(filter.matches(mediumHeavy))
        XCTAssertFalse(filter.matches(lightHeavy))
        XCTAssertFalse(filter.matches(light))
        XCTAssertTrue(filter.matches(bodyweight))
    }

    func testDumbbellLoadBodyweightSelectionMatchesOnlyBodyweightWorkouts() {
        let heavy = workout(id: "h", title: "T", trainer: "x", duration: 20,
                            bodyFocus: "total-body", muscleGroups: ["core"],
                            equipment: ["dumbbells"], dumbbellLoad: ["heavy"])
        let bodyweight = workout(id: "bw", title: "T", trainer: "x", duration: 20,
                                 bodyFocus: "total-body", muscleGroups: ["core"],
                                 equipment: ["no-equipment"], dumbbellLoad: ["bodyweight"])

        var filter = WorkoutFilter()
        filter.dumbbellLoad = ["bodyweight"]

        XCTAssertFalse(filter.matches(heavy))
        XCTAssertTrue(filter.matches(bodyweight))
    }

    func testDumbbellLoadBodyweightDoesNotLoosenSelectedWeightedBuckets() {
        let heavy = workout(id: "h", title: "T", trainer: "x", duration: 20,
                            bodyFocus: "total-body", muscleGroups: ["core"],
                            equipment: ["dumbbells"], dumbbellLoad: ["heavy"])
        let mediumHeavy = workout(id: "mh", title: "T", trainer: "x", duration: 20,
                                  bodyFocus: "total-body", muscleGroups: ["core"],
                                  equipment: ["dumbbells"], dumbbellLoad: ["medium", "heavy"])
        let light = workout(id: "l", title: "T", trainer: "x", duration: 20,
                            bodyFocus: "total-body", muscleGroups: ["core"],
                            equipment: ["dumbbells"], dumbbellLoad: ["light"])
        let bodyweight = workout(id: "bw", title: "T", trainer: "x", duration: 20,
                                 bodyFocus: "total-body", muscleGroups: ["core"],
                                 equipment: ["no-equipment"], dumbbellLoad: ["bodyweight"])

        var filter = WorkoutFilter()
        filter.dumbbellLoad = ["light", "bodyweight"]

        XCTAssertFalse(filter.matches(heavy))
        XCTAssertFalse(filter.matches(mediumHeavy))
        XCTAssertTrue(filter.matches(light))
        XCTAssertTrue(filter.matches(bodyweight))
    }

    func testDumbbellLoadNilOrEmptyNeverMatchesActiveFilter() {
        let noLoad = workout(id: "none", title: "T", trainer: "x", duration: 20,
                             bodyFocus: "total-body", muscleGroups: ["core"],
                             equipment: ["dumbbells"], dumbbellLoad: nil)
        let emptyLoad = workout(id: "empty", title: "T", trainer: "x", duration: 20,
                                bodyFocus: "total-body", muscleGroups: ["core"],
                                equipment: ["dumbbells"], dumbbellLoad: [])

        var filter = WorkoutFilter()
        XCTAssertTrue(filter.matches(noLoad), "no active filter matches everything")

        filter.dumbbellLoad = ["heavy"]
        XCTAssertFalse(filter.matches(noLoad))
        XCTAssertFalse(filter.matches(emptyLoad))
    }

    func testTrainerFilterMatchesSelectedTrainerSlugs() {
        var filter = WorkoutFilter()
        filter.trainers = ["sam", "kim"]

        XCTAssertFalse(filter.matches(tenMinuteTotal))
        XCTAssertTrue(filter.matches(elevenMinuteUpper))
        XCTAssertTrue(filter.matches(twentyMinuteLower))
        XCTAssertFalse(filter.matches(thirtyOneMinuteTotalBodyweight))
    }

    func testSearchCombinesWithFacetFilters() {
        let withEpisode = workout(
            id: "ep-10", title: "Strength with Sam", trainer: "sam",
            duration: 10, bodyFocus: "upper-body",
            muscleGroups: ["chest"], equipment: ["dumbbells"],
            episode: 10
        )
        var filter = WorkoutFilter()
        filter.search = "1"
        filter.durations = [10]
        filter.equipment = ["dumbbells"]

        XCTAssertTrue(filter.matches(withEpisode))
        // No episode -> never matches a search.
        XCTAssertFalse(filter.matches(tenMinuteTotal))
        XCTAssertFalse(filter.matches(twentyMinuteLower))
    }

    func testSearchMatchesEpisodeNumberExactly() {
        let withEpisode = workout(
            id: "ep-42", title: "Strength with Kim", trainer: "kim",
            duration: 20, bodyFocus: "lower-body",
            muscleGroups: ["glutes"], equipment: ["mat"],
            episode: 42
        )
        var filter = WorkoutFilter()
        filter.search = "42"

        XCTAssertFalse(filter.matches(tenMinuteTotal))
        XCTAssertTrue(filter.matches(withEpisode))
    }

    func testSearchMatchesEpisodeNumberByPrefix() {
        let ep2 = workout(id: "ep-2", title: "T", trainer: "x",
                          duration: 10, bodyFocus: "total-body",
                          muscleGroups: ["core"], equipment: ["mat"], episode: 2)
        let ep20 = workout(id: "ep-20", title: "T", trainer: "x",
                           duration: 10, bodyFocus: "total-body",
                           muscleGroups: ["core"], equipment: ["mat"], episode: 20)
        let ep21 = workout(id: "ep-21", title: "T", trainer: "x",
                           duration: 10, bodyFocus: "total-body",
                           muscleGroups: ["core"], equipment: ["mat"], episode: 21)
        let ep202 = workout(id: "ep-202", title: "T", trainer: "x",
                            duration: 10, bodyFocus: "total-body",
                            muscleGroups: ["core"], equipment: ["mat"], episode: 202)
        let ep3 = workout(id: "ep-3", title: "T", trainer: "x",
                          duration: 10, bodyFocus: "total-body",
                          muscleGroups: ["core"], equipment: ["mat"], episode: 3)

        var filter = WorkoutFilter()
        filter.search = "2"

        XCTAssertTrue(filter.matches(ep2))
        XCTAssertTrue(filter.matches(ep20))
        XCTAssertTrue(filter.matches(ep21))
        XCTAssertTrue(filter.matches(ep202))
        XCTAssertFalse(filter.matches(ep3))
    }

    func testSearchIgnoresWorkoutsWithoutAnEpisode() {
        var filter = WorkoutFilter()
        filter.search = "1"

        XCTAssertFalse(filter.matches(tenMinuteTotal))
        XCTAssertFalse(filter.matches(elevenMinuteUpper))
        XCTAssertFalse(filter.matches(twentyMinuteLower))
        XCTAssertFalse(filter.matches(thirtyOneMinuteTotalBodyweight))
    }

    func testClearFacetsKeepsSearchText() {
        var filter = WorkoutFilter()
        filter.search = "strength"
        filter.durations = [10]
        filter.trainers = ["sam"]
        filter.bodyFocus = ["upper-body"]
        filter.muscleGroups = ["back"]
        filter.equipment = ["dumbbells"]
        filter.dumbbellLoad = ["heavy"]

        XCTAssertEqual(filter.activeFacetCount, 6)

        filter.clearFacets()

        XCTAssertEqual(filter.search, "strength")
        XCTAssertEqual(filter.activeFacetCount, 0)
        XCTAssertTrue(filter.dumbbellLoad.isEmpty)
        XCTAssertFalse(filter.isEmpty)
    }

    func testBundledCatalogRepresentativeFacetCombinations() throws {
        let workouts = try bundledWorkouts()

        // Sanity-check the bundle is present and reasonably complete, without
        // pinning an exact count that breaks every catalog refresh.
        XCTAssertGreaterThan(workouts.count, 800, "bundled catalog looks truncated")
        XCTAssertGreaterThan(workouts.filter { $0.appleURL == nil }.count, 0,
                             "expected some fallback workouts without an Apple URL")

        // Representative facet combinations: the filter logic works if each
        // returns at least one workout.
        XCTAssertGreaterThan(
            countMatches(
                workouts,
                durations: [20],
                bodyFocus: ["upper-body"],
                muscleGroups: ["shoulders"],
                equipment: ["dumbbells"]
            ),
            0,
            "20-min upper-body shoulder dumbbell workouts"
        )
        XCTAssertGreaterThan(
            countMatches(
                workouts,
                durations: [30],
                bodyFocus: ["lower-body"],
                muscleGroups: ["glutes"],
                equipment: ["mat"]
            ),
            0,
            "30-min lower-body glutes mat workouts"
        )
        XCTAssertGreaterThan(
            countMatches(
                workouts,
                durations: [10],
                bodyFocus: ["lower-body"],
                muscleGroups: ["glutes"],
                equipment: ["no-equipment"]
            ),
            0,
            "10-min lower-body glutes bodyweight workouts"
        )

        // Prefix search on real episode numbers: '1' should match strictly more
        // episodes than '2' in any reasonable catalog.
        let searchTwo = countMatches(workouts, search: "2")
        let searchOne = countMatches(workouts, search: "1")
        XCTAssertGreaterThan(searchTwo, 0, "episode prefix search '2' should match")
        XCTAssertGreaterThan(searchOne, 0, "episode prefix search '1' should match")
        XCTAssertGreaterThan(searchOne, searchTwo,
                             "prefix '1' should match more episodes than prefix '2'")
    }

    func testEveryBundledFilterOptionHasAtLeastOneWorkout() throws {
        let workouts = try bundledWorkouts()
        let taxonomy = try bundledTaxonomy()

        for duration in [10, 20, 30] {
            XCTAssertGreaterThan(countMatches(workouts, durations: [duration]), 0, "\(duration) min")
        }
        for bodyFocus in taxonomy.bodyFocus.keys {
            XCTAssertGreaterThan(countMatches(workouts, bodyFocus: [bodyFocus]), 0, bodyFocus)
        }
        for muscleGroup in taxonomy.muscleGroups.keys {
            XCTAssertGreaterThan(countMatches(workouts, muscleGroups: [muscleGroup]), 0, muscleGroup)
        }
        for equipment in taxonomy.equipment.keys {
            XCTAssertGreaterThan(countMatches(workouts, equipment: [equipment]), 0, equipment)
        }
    }

    func testBundledMatAndNoEquipmentFiltersAreDistinct() throws {
        let workouts = try bundledWorkouts()
        let matIDs = matchedIDs(workouts, equipment: ["mat"])
        let noEquipmentIDs = matchedIDs(workouts, equipment: ["no-equipment"])

        XCTAssertGreaterThan(matIDs.count, 0, "mat equipment filter")
        XCTAssertGreaterThan(noEquipmentIDs.count, 0, "no-equipment filter")
        XCTAssertTrue(matIDs.isDisjoint(with: noEquipmentIDs),
                      "mat and no-equipment should never overlap")
    }

    func testBundledDumbbellLoadFiltersDoNotIncludeUnselectedWeightedBuckets() throws {
        let workouts = try bundledWorkouts()
        let weightedBuckets: Set<String> = ["light", "medium", "heavy"]

        for selection in [Set(["light"]), Set(["medium"]), Set(["heavy"]),
                          Set(["medium", "heavy"])] {
            let matches = matchedWorkouts(workouts, dumbbellLoad: selection)
            XCTAssertGreaterThan(matches.count, 0, "\(selection) should match bundled workouts")

            for workout in matches {
                let workoutBuckets = Set(workout.facets.dumbbellLoad ?? [])
                let workoutWeightedBuckets = workoutBuckets.intersection(weightedBuckets)

                XCTAssertTrue(
                    workoutWeightedBuckets.isEmpty || workoutWeightedBuckets == selection,
                    "\(workout.id) matched \(selection) with load \(workoutBuckets)"
                )
            }
        }
    }
}

private func bundledWorkouts() throws -> [Workout] {
    try decodeBundleResource("strength")
}

private func bundledTaxonomy() throws -> Taxonomy {
    try decodeBundleResource("taxonomy")
}

private func decodeBundleResource<T: Decodable>(_ name: String) throws -> T {
    let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "json"))
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(T.self, from: data)
}

private func countMatches(
    _ workouts: [Workout],
    search: String = "",
    durations: Set<Int> = [],
    trainers: Set<String> = [],
    bodyFocus: Set<String> = [],
    muscleGroups: Set<String> = [],
    equipment: Set<String> = [],
    dumbbellLoad: Set<String> = []
) -> Int {
    var filter = WorkoutFilter()
    filter.search = search
    filter.durations = durations
    filter.trainers = trainers
    filter.bodyFocus = bodyFocus
    filter.muscleGroups = muscleGroups
    filter.equipment = equipment
    filter.dumbbellLoad = dumbbellLoad

    return workouts.filter(filter.matches).count
}

private func matchedWorkouts(
    _ workouts: [Workout],
    search: String = "",
    durations: Set<Int> = [],
    trainers: Set<String> = [],
    bodyFocus: Set<String> = [],
    muscleGroups: Set<String> = [],
    equipment: Set<String> = [],
    dumbbellLoad: Set<String> = []
) -> [Workout] {
    var filter = WorkoutFilter()
    filter.search = search
    filter.durations = durations
    filter.trainers = trainers
    filter.bodyFocus = bodyFocus
    filter.muscleGroups = muscleGroups
    filter.equipment = equipment
    filter.dumbbellLoad = dumbbellLoad

    return workouts.filter(filter.matches)
}

private func matchedIDs(
    _ workouts: [Workout],
    search: String = "",
    durations: Set<Int> = [],
    trainers: Set<String> = [],
    bodyFocus: Set<String> = [],
    muscleGroups: Set<String> = [],
    equipment: Set<String> = [],
    dumbbellLoad: Set<String> = []
) -> Set<String> {
    Set(matchedWorkouts(
        workouts,
        search: search,
        durations: durations,
        trainers: trainers,
        bodyFocus: bodyFocus,
        muscleGroups: muscleGroups,
        equipment: equipment,
        dumbbellLoad: dumbbellLoad
    ).map(\.id))
}

private func workout(
    id: String,
    title: String,
    trainer: String,
    duration: Int,
    bodyFocus: String,
    muscleGroups: [String],
    equipment: [String],
    episode: Int? = nil,
    releaseDate: String? = nil,
    summary: String? = nil,
    moves: [String] = [],
    dumbbellLoad: [String]? = nil
) -> Workout {
    Workout(
        id: id,
        discipline: "strength",
        title: title,
        trainer: trainer,
        durationMinutes: duration,
        episode: episode,
        appleUrl: "https://fitness.apple.com/us/workout/\(id)",
        summary: summary,
        releaseDate: releaseDate,
        facets: Facets(
            bodyFocus: bodyFocus,
            muscleGroups: muscleGroups,
            equipment: equipment,
            dumbbells: nil,
            dumbbellLoad: dumbbellLoad
        ),
        moves: moves,
        moveSequence: nil,
        coachNotes: nil
    )
}
