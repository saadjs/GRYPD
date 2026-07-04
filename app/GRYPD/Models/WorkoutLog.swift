import Foundation
import SwiftData

enum WeightUnit: String, Codable, CaseIterable, Identifiable {
    case lb, kg
    var id: String { rawValue }
    var label: String { rawValue }

    func convertedWeight(_ weight: Double, to targetUnit: WeightUnit) -> Double {
        switch (self, targetUnit) {
        case (.lb, .lb), (.kg, .kg):
            return weight
        case (.kg, .lb):
            return weight * 2.2046226218
        case (.lb, .kg):
            return weight / 2.2046226218
        }
    }
}

/// A logged performance of a workout. The only persistent, user-owned data.
/// Joins to the catalog by value on `workoutId` (a stable Apple id) — never a
/// SwiftData relationship, because the catalog is replaced wholesale on update.
@Model
final class WorkoutLog {
    var id: UUID = UUID()
    var workoutId: String = ""
    var performedAt: Date = Date.now
    var note: String?
    /// Optional active-calorie estimate, hand-entered by the user at log time.
    var activeEnergyKcal: Double?
    @Relationship(deleteRule: .cascade, inverse: \MoveEntry.log)
    var moveEntries: [MoveEntry] = []

    init(workoutId: String, performedAt: Date = .now, note: String? = nil) {
        self.id = UUID()
        self.workoutId = workoutId
        self.performedAt = performedAt
        self.note = note
    }

    /// A session is *matched* once it's tied to a catalog workout.
    var isMatched: Bool { !workoutId.isEmpty }
}

/// One completed set for a logged move. Strength sessions are filled in after
/// the workout, so a set can carry weight, reps, time, or any combination.
@Model
final class SetEntry {
    var order: Int = 0
    var weightValue: Double = 0
    var weightUnitRaw: String = WeightUnit.lb.rawValue
    var reps: Int?
    var seconds: Int?
    var moveEntry: MoveEntry?

    var weightUnit: WeightUnit {
        get { WeightUnit(rawValue: weightUnitRaw) ?? .lb }
        set { weightUnitRaw = newValue.rawValue }
    }

    init(order: Int = 0,
         weightValue: Double = 0,
         weightUnit: WeightUnit = .lb,
         reps: Int? = nil,
         seconds: Int? = nil) {
        self.order = order
        self.weightValue = weightValue
        self.weightUnitRaw = weightUnit.rawValue
        self.reps = reps
        self.seconds = seconds
    }
}

/// One exercise entry within a session, optionally tied to a catalog move slug.
@Model
final class MoveEntry {
    var moveSlug: String?
    var label: String = ""
    @Relationship(deleteRule: .cascade, inverse: \SetEntry.moveEntry)
    var sets: [SetEntry] = []
    var log: WorkoutLog?

    init(moveSlug: String?, label: String) {
        self.moveSlug = moveSlug
        self.label = label
    }

    convenience init(moveSlug: String?,
                     label: String,
                     weightValue: Double = 0,
                     weightUnit: WeightUnit = .lb,
                     reps: Int? = nil,
                     seconds: Int? = nil) {
        self.init(moveSlug: moveSlug, label: label)
        if weightValue > 0 || (reps ?? 0) > 0 || (seconds ?? 0) > 0 {
            let set = SetEntry(order: 0,
                               weightValue: weightValue,
                               weightUnit: weightUnit,
                               reps: reps,
                               seconds: seconds)
            set.moveEntry = self
            self.sets = [set]
        }
    }

    var orderedSets: [SetEntry] {
        sets.sorted { lhs, rhs in
            if lhs.order == rhs.order { return lhs.persistentModelID.hashValue < rhs.persistentModelID.hashValue }
            return lhs.order < rhs.order
        }
    }

    /// Best set for display/progression: highest weight; if all sets are
    /// weightless, highest reps; otherwise longest time.
    var topSet: SetEntry? {
        orderedSets.max { lhs, rhs in
            let left = setRank(lhs)
            let right = setRank(rhs)
            if left.weight != right.weight { return left.weight < right.weight }
            if left.reps != right.reps { return left.reps < right.reps }
            if left.seconds != right.seconds { return left.seconds < right.seconds }
            return lhs.order > rhs.order
        }
    }

    private func setRank(_ set: SetEntry) -> (weight: Double, reps: Int, seconds: Int) {
        (max(0, set.weightValue), max(0, set.reps ?? 0), max(0, set.seconds ?? 0))
    }
}
