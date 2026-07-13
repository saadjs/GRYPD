import XCTest
@testable import GRYPD

final class LogExerciseDraftTests: XCTestCase {
    func testMovePickerKeepsLoggedExercisesVisibleAndMarksThemLogged() {
        let taxonomy = Taxonomy(bodyFocus: [:], muscleGroups: [:], equipment: [:],
                                dumbbells: [:], trainers: [:],
                                moves: ["squat": "Squat", "deadlift": "Deadlift"],
                                disciplines: [:])

        let rows = MovePickerView.makeRows(taxonomy: taxonomy,
                                           customMoves: [],
                                           logged: ["squat"])

        XCTAssertEqual(rows.map(\.slug), ["deadlift", "squat"])
        XCTAssertFalse(rows[0].isLogged)
        XCTAssertTrue(rows[1].isLogged)
    }

    func testMovePickerMarksLoggedCustomExerciseWithoutDuplicatingCatalogMoves() {
        let taxonomy = Taxonomy(bodyFocus: [:], muscleGroups: [:], equipment: [:],
                                dumbbells: [:], trainers: [:],
                                moves: ["squat": "Catalog Squat"],
                                disciplines: [:])
        let customMoves = [
            CustomMove(slug: "squat", label: "Custom Squat"),
            CustomMove(slug: "carry", label: "Suitcase Carry")
        ]

        let rows = MovePickerView.makeRows(taxonomy: taxonomy,
                                           customMoves: customMoves,
                                           logged: ["carry"])

        XCTAssertEqual(rows.map(\.slug), ["squat", "carry"])
        XCTAssertEqual(rows.first?.label, "Catalog Squat")
        XCTAssertEqual(rows.last?.label, "Suitcase Carry")
        XCTAssertEqual(rows.map(\.isLogged), [false, true])
    }

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
        squat.sets.append(SetEntry(order: 1, weightValue: 40, weightUnit: .lb,
                                   reps: 8, repsInReserve: 2, seconds: 35))

        let drafts = LogExerciseDrafts.make(workoutMoves: ["squat", "deadlift"],
                                            existing: [squat, custom],
                                            defaultUnit: .lb) { slug in
            slug == "deadlift" ? "Deadlift" : "Catalog \(slug)"
        }

        // Existing entries keep their saved order (squat, then the custom move);
        // the unlogged catalog move (deadlift) is appended at the end.
        XCTAssertEqual(drafts.map(\.label), ["Goblet Squat", "Suitcase Carry", "Deadlift"])
        XCTAssertEqual(drafts.map(\.moveSlug), ["squat", nil, "deadlift"])
        XCTAssertEqual(drafts[0].sets.map(\.weight), [35, 40])
        XCTAssertEqual(drafts[0].sets.map(\.reps), [10, 8])
        XCTAssertEqual(drafts[0].lastSetRepsInReserve, 2)
        XCTAssertEqual(drafts[0].sets.map(\.seconds), [40, 35])
        XCTAssertEqual(drafts[1].sets.first?.weight ?? 0, 97.0033953592, accuracy: 0.000001)
        XCTAssertEqual(drafts[2].sets.map(\.weight), [nil])
    }

    func testSavedExerciseOrderWinsOverCatalogOrder() {
        // User dragged the catalog order [a, b, c] into [c, a]; b was left empty
        // (unlogged). Re-editing must show c, a first — the saved order — then
        // append the unlogged catalog move b at the end.
        let c = MoveEntry(moveSlug: "c", label: "C", weightValue: 30, weightUnit: .lb)
        let a = MoveEntry(moveSlug: "a", label: "A", weightValue: 20, weightUnit: .lb)

        let drafts = LogExerciseDrafts.make(workoutMoves: ["a", "b", "c"],
                                            existing: [c, a],
                                            defaultUnit: .lb) { $0.uppercased() }

        XCTAssertEqual(drafts.map(\.moveSlug), ["c", "a", "b"])
    }

    func testFreshMovesKeepDefaultsAsSuggestionsButLoggedWeightsWin() {
        // squat already logged at 40 — must be preserved, not overwritten.
        let squat = MoveEntry(moveSlug: "squat", label: "Squat", weightValue: 40, weightUnit: .lb)
        let defaults = DumbbellDefaults(light: 10, medium: 15, heavy: 25, unit: .lb)

        let drafts = LogExerciseDrafts.make(
            workoutMoves: ["squat", "lateral-raise", "plank"],
            existing: [squat],
            defaultUnit: .lb,
            dumbbellDefaults: defaults) { slug in slug.capitalized }

        // Saved values remain real data. Defaults are only UI suggestions, so
        // untouched catalog exercises stay empty and cannot be persisted silently.
        XCTAssertEqual(drafts.map(\.moveSlug), ["squat", "lateral-raise", "plank"])
        XCTAssertEqual(drafts.map { $0.sets.first?.weight }, [40, nil, nil])
        XCTAssertNil(drafts[1].sets.first?.reps)
        XCTAssertNil(drafts[1].sets.first?.seconds)
        XCTAssertFalse(drafts[1].shouldPersist)
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

    func testEffortClearsWhenRatedLastWeightedSetIsRemoved() {
        let first = SetDraft(weight: 30, reps: 10)
        let rated = SetDraft(weight: 40, reps: 8)
        var draft = LogExerciseDraft(moveSlug: "squat",
                                     label: "Squat",
                                     sets: [first, rated])
        draft.setLastSetRepsInReserve(2)

        draft.sets.removeLast()
        draft.reconcileLastSetEffort()

        XCTAssertNil(draft.lastSetRepsInReserve)
        XCTAssertNil(draft.effortSetID)
    }

    func testEffortClearsWhenRatedSetBecomesUnweighted() {
        var draft = LogExerciseDraft(moveSlug: "squat",
                                     label: "Squat",
                                     sets: [SetDraft(weight: 40, reps: 8)])
        draft.setLastSetRepsInReserve(1)

        draft.sets[0].reps = nil
        draft.reconcileLastSetEffort()

        XCTAssertNil(draft.lastSetRepsInReserve)
        XCTAssertNil(draft.effortSetID)
    }
}
