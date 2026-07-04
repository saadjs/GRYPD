import XCTest
@testable import GRYPD

final class LogExerciseDraftTests: XCTestCase {
    func testDraftsSeedCatalogMovesWithEditedLabelsAndCustomEntries() {
        let squat = MoveEntry(moveSlug: "squat",
                              label: "Goblet Squat",
                              weightValue: 35,
                              weightUnit: .lb,
                              reps: 10,
                              seconds: 40)
        let custom = MoveEntry(moveSlug: nil,
                               label: "Suitcase Carry",
                               weightValue: 44,
                               weightUnit: .kg,
                               reps: 8)
        squat.sets.append(SetEntry(order: 1, weightValue: 40, weightUnit: .lb, reps: 8, seconds: 35))

        let drafts = LogExerciseDrafts.make(workoutMoves: ["squat", "deadlift"],
                                            existing: [squat, custom],
                                            defaultUnit: .lb) { slug in
            slug == "deadlift" ? "Deadlift" : "Catalog \(slug)"
        }

        XCTAssertEqual(drafts.map(\.label), ["Goblet Squat", "Deadlift", "Suitcase Carry"])
        XCTAssertEqual(drafts.map(\.moveSlug), ["squat", "deadlift", nil])
        XCTAssertEqual(drafts[0].sets.map(\.weight), [35, 40])
        XCTAssertEqual(drafts[0].sets.map(\.reps), [10, 8])
        XCTAssertEqual(drafts[0].sets.map(\.seconds), [40, 35])
        XCTAssertEqual(drafts[1].sets.map(\.weight), [nil])
        XCTAssertEqual(drafts[2].sets.first?.weight ?? 0, 97.0033953592, accuracy: 0.000001)
    }

    func testFreshMovesAutoFillFromDumbbellDefaultsButLoggedWeightsWin() {
        // squat already logged at 40 — must be preserved, not overwritten.
        let squat = MoveEntry(moveSlug: "squat", label: "Squat", weightValue: 40, weightUnit: .lb)
        let defaults = DumbbellDefaults(light: 10, medium: 15, heavy: 25, unit: .lb)

        let drafts = LogExerciseDrafts.make(
            workoutMoves: ["squat", "lateral-raise", "plank"],
            existing: [squat],
            defaultUnit: .lb,
            dumbbellDefaults: defaults) { slug in slug.capitalized }

        // squat keeps its logged 40; lateral-raise auto-fills light (10);
        // plank is bodyweight so stays empty.
        XCTAssertEqual(drafts.map(\.moveSlug), ["squat", "lateral-raise", "plank"])
        XCTAssertEqual(drafts.map { $0.sets.first?.weight }, [40, 10, nil])
        XCTAssertNil(drafts[1].sets.first?.reps)
        XCTAssertNil(drafts[1].sets.first?.seconds)
        XCTAssertFalse(drafts[2].shouldPersist)
    }

    func testDraftPersistenceRequiresLabelAndNonEmptySet() {
        XCTAssertTrue(LogExerciseDraft(moveSlug: nil,
                                       label: "  Carry  ",
                                       sets: [SetDraft(weight: 20)]).shouldPersist)
        XCTAssertTrue(LogExerciseDraft(moveSlug: nil,
                                       label: "Plank",
                                       sets: [SetDraft(seconds: 45)]).shouldPersist)
        XCTAssertTrue(LogExerciseDraft(moveSlug: nil,
                                       label: "Push-Up",
                                       sets: [SetDraft(reps: 12)]).shouldPersist)
        XCTAssertFalse(LogExerciseDraft(moveSlug: nil,
                                        label: "  ",
                                        sets: [SetDraft(weight: 20)]).shouldPersist)
        XCTAssertFalse(LogExerciseDraft(moveSlug: nil,
                                        label: "Carry",
                                        sets: [SetDraft(weight: 0, reps: nil, seconds: nil)]).shouldPersist)
        XCTAssertFalse(LogExerciseDraft(moveSlug: nil,
                                        label: "Carry",
                                        sets: [SetDraft(reps: nil, seconds: nil)]).shouldPersist)
    }
}
