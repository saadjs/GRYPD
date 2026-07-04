import Foundation

struct SetDraft: Identifiable, Equatable {
    static let defaultReps = 8
    static let defaultSeconds = 30
    static var empty: SetDraft {
        SetDraft(reps: nil, seconds: nil)
    }

    let id: UUID
    var weight: Double?
    var reps: Int?
    var seconds: Int?

    init(id: UUID = UUID(),
         weight: Double? = nil,
         reps: Int? = Self.defaultReps,
         seconds: Int? = Self.defaultSeconds) {
        self.id = id
        self.weight = weight
        self.reps = reps
        self.seconds = seconds
    }

    var isEmpty: Bool {
        (weight ?? 0) <= 0 && (reps ?? 0) <= 0 && (seconds ?? 0) <= 0
    }
}

/// Editable row state for the logging sheet. Kept outside the view so the
/// catalog merge rules are testable without rendering SwiftUI.
struct LogExerciseDraft: Identifiable, Equatable {
    let id: UUID
    var moveSlug: String?
    var label: String
    var sets: [SetDraft]

    init(id: UUID = UUID(),
         moveSlug: String?,
         label: String,
         sets: [SetDraft] = []) {
        self.id = id
        self.moveSlug = moveSlug
        self.label = label
        self.sets = sets
    }

    var trimmedLabel: String {
        label.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var shouldPersist: Bool {
        !trimmedLabel.isEmpty && sets.contains { !$0.isEmpty }
    }
}

enum LogExerciseDrafts {
    /// Rows to show: the matched workout's moves, pre-filled from existing log
    /// entries, plus logged entries the workout no longer lists and custom rows.
    ///
    /// A fresh workout move with no logged weight is auto-filled from the user's
    /// configured `dumbbellDefaults` (by the move's `DumbbellTier`); already-logged
    /// weights are always preserved, so editing a session never clobbers real data.
    static func make(workoutMoves: [String],
                     existing: [MoveEntry],
                     defaultUnit: WeightUnit,
                     dumbbellDefaults: DumbbellDefaults? = nil,
                     moveLabel: (String) -> String) -> [LogExerciseDraft] {
        var bySlug: [String: MoveEntry] = [:]
        for entry in existing {
            if let slug = entry.moveSlug {
                bySlug[slug] = entry
            }
        }

        var drafts: [LogExerciseDraft] = []
        var covered = Set<String>()
        for slug in workoutMoves {
            covered.insert(slug)
            let logged = bySlug[slug]
            let sets = logged.map { setDrafts(for: $0, defaultUnit: defaultUnit) } ?? [
                SetDraft(weight: dumbbellDefaults?.weight(forMoveSlug: slug), reps: nil, seconds: nil)
            ]
            drafts.append(LogExerciseDraft(moveSlug: slug,
                                           label: logged?.label ?? moveLabel(slug),
                                           sets: sets))
        }

        for entry in existing where !(entry.moveSlug.map(covered.contains) ?? false) {
            drafts.append(LogExerciseDraft(moveSlug: entry.moveSlug,
                                           label: entry.label,
                                           sets: setDrafts(for: entry, defaultUnit: defaultUnit)))
        }
        return drafts
    }

    private static func setDrafts(for entry: MoveEntry, defaultUnit: WeightUnit) -> [SetDraft] {
        let drafts = entry.orderedSets.map { set in
            SetDraft(weight: positiveWeight(set.weightUnit.convertedWeight(set.weightValue, to: defaultUnit)),
                     reps: positiveInt(set.reps),
                     seconds: positiveInt(set.seconds))
        }
        return drafts.isEmpty ? [.empty] : drafts
    }

    private static func positiveWeight(_ value: Double) -> Double? {
        value > 0 ? value : nil
    }

    private static func positiveInt(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return value
    }
}
