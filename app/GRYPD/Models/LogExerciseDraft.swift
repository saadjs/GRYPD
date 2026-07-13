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
    var lastSetRepsInReserve: Int?
    private(set) var effortSetID: UUID?

    init(id: UUID = UUID(),
         moveSlug: String?,
         label: String,
         sets: [SetDraft] = [],
         lastSetRepsInReserve: Int? = nil) {
        self.id = id
        self.moveSlug = moveSlug
        self.label = label
        self.sets = sets
        self.lastSetRepsInReserve = lastSetRepsInReserve
        self.effortSetID = lastSetRepsInReserve == nil
            ? nil
            : sets.last { ($0.weight ?? 0) > 0 && ($0.reps ?? 0) > 0 }?.id
    }

    var trimmedLabel: String {
        label.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var shouldPersist: Bool {
        !trimmedLabel.isEmpty && sets.contains { !$0.isEmpty }
    }

    mutating func setLastSetRepsInReserve(_ value: Int?) {
        lastSetRepsInReserve = value
        effortSetID = value == nil ? nil : lastWeightedSetID
    }

    /// A rating belongs to a specific last weighted set. Editing or deleting sets
    /// can change that identity, in which case retaining the rating would silently
    /// apply it to a set the user never rated.
    mutating func reconcileLastSetEffort() {
        guard effortSetID == lastWeightedSetID else {
            lastSetRepsInReserve = nil
            effortSetID = nil
            return
        }
    }

    private var lastWeightedSetID: UUID? {
        sets.last { ($0.weight ?? 0) > 0 && ($0.reps ?? 0) > 0 }?.id
    }
}

enum LogExerciseDrafts {
    /// Rows to show: the session's already-logged entries first, in the exact
    /// order they were saved (the user's drag-reordered order), followed by any
    /// catalog moves not yet logged, in catalog order.
    ///
    /// Pass `existing` already ordered — callers use `WorkoutLog.orderedMoveEntries`
    /// so a re-edit reproduces the user's chosen exercise order verbatim. For a
    /// brand-new session `existing` is empty, so the result is plain catalog order.
    ///
    /// A not-yet-logged catalog move is auto-filled from the user's configured
    /// `dumbbellDefaults` (by the move's `DumbbellTier`); already-logged weights
    /// are always preserved, so editing a session never clobbers real data.
    static func make(workoutMoves: [String],
                     existing: [MoveEntry],
                     defaultUnit: WeightUnit,
                     dumbbellDefaults: DumbbellDefaults? = nil,
                     moveLabel: (String) -> String) -> [LogExerciseDraft] {
        var drafts: [LogExerciseDraft] = []
        var loggedSlugs = Set<String>()

        // The user's saved order wins: emit existing entries exactly as passed.
        for entry in existing {
            if let slug = entry.moveSlug { loggedSlugs.insert(slug) }
            drafts.append(LogExerciseDraft(moveSlug: entry.moveSlug,
                                           label: entry.label,
                                           sets: setDrafts(for: entry, defaultUnit: defaultUnit),
                                           lastSetRepsInReserve: entry.orderedSets
                                            .last(where: isWeightedRepSet)?
                                            .repsInReserve))
        }

        // Append catalog moves the user hasn't logged yet, in catalog order. The
        // configured dumbbell value is a suggestion in the UI, not completed
        // workout data, so it must never be written into a fresh draft silently.
        for slug in workoutMoves where !loggedSlugs.contains(slug) {
            drafts.append(LogExerciseDraft(moveSlug: slug,
                                           label: moveLabel(slug),
                                           sets: [.empty]))
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

    private static func isWeightedRepSet(_ set: SetEntry) -> Bool {
        set.weightValue > 0 && (set.reps ?? 0) > 0
    }
}
