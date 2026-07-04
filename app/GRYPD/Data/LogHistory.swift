import Foundation
import SwiftData

/// Read helpers over the SwiftData log store. Kept as plain functions taking a
/// ModelContext so views stay thin.
enum LogHistory {

    /// Map of workoutId -> most recent performedAt, for "last done" in Browse.
    /// Defensive: only sessions tied to a catalog workout are counted.
    @MainActor
    static func lastDoneByWorkout(_ logs: [WorkoutLog], catalog: CatalogStore) -> [String: Date] {
        var out: [String: Date] = [:]
        for log in logs where !log.workoutId.isEmpty {
            guard let workoutId = catalog.canonicalWorkoutId(for: log.workoutId) else { continue }
            if let existing = out[workoutId] {
                if log.performedAt > existing { out[workoutId] = log.performedAt }
            } else {
                out[workoutId] = log.performedAt
            }
        }
        return out
    }

    /// All sessions for a workout, newest first.
    static func sessions(for workoutId: String, in ctx: ModelContext) -> [WorkoutLog] {
        let desc = FetchDescriptor<WorkoutLog>(
            predicate: #Predicate { $0.workoutId == workoutId },
            sortBy: [SortDescriptor(\.performedAt, order: .reverse)]
        )
        return (try? ctx.fetch(desc)) ?? []
    }

    /// One point in a move's progression.
    struct MovePoint: Identifiable {
        let id = UUID()
        let date: Date
        let weight: Double
        let unit: WeightUnit
        let workoutId: String
        let workoutTitle: String
    }

    /// A move's weight over time, GROUPED by source workout so contexts aren't
    /// naively merged (the same move loads differently across workouts).
    @MainActor
    static func moveProgression(moveSlug: String,
                                in ctx: ModelContext,
                                catalog: CatalogStore) -> [(workoutId: String, title: String, points: [MovePoint])] {
        let all = (try? ctx.fetch(FetchDescriptor<WorkoutLog>())) ?? []
        var byWorkout: [String: [MovePoint]] = [:]
        for log in all where !log.workoutId.isEmpty {
            let workout = catalog.workout(id: log.workoutId)
            let workoutId = workout?.id ?? log.workoutId
            let title = workout?.title ?? "Unavailable workout"
            for entry in log.moveEntries where entry.moveSlug == moveSlug {
                guard let set = entry.topSet else { continue }
                byWorkout[workoutId, default: []].append(
                    MovePoint(date: log.performedAt, weight: set.weightValue,
                              unit: set.weightUnit, workoutId: workoutId, workoutTitle: title)
                )
            }
        }
        return byWorkout
            .map { (workoutId: $0.key,
                    title: catalog.workout(id: $0.key)?.title ?? "Unavailable workout",
                    points: $0.value.sorted { $0.date < $1.date }) }
            .sorted { $0.title < $1.title }
    }
}
