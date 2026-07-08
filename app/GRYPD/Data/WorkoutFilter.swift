import Foundation

/// Pure in-memory filter over the catalog. Instant at 531 objects.
struct WorkoutFilter: Equatable {
    var search: String = ""
    var durations: Set<Int> = []        // buckets: 10, 20, 30
    var trainers: Set<String> = []      // slugs
    var bodyFocus: Set<String> = []     // slugs
    var muscleGroups: Set<String> = []  // slugs (match ANY)
    var equipment: Set<String> = []     // slugs (match ANY)
    var dumbbellLoad: Set<String> = []  // light/medium/heavy/bodyweight

    /// Active facet filters (search is handled separately for the "clear" affordance).
    var activeFacetCount: Int {
        durations.count + trainers.count + bodyFocus.count
            + muscleGroups.count + equipment.count + dumbbellLoad.count
    }
    var isEmpty: Bool {
        search.trimmingCharacters(in: .whitespaces).isEmpty && activeFacetCount == 0
    }

    func matches(_ w: Workout) -> Bool {
        matches(w, taxonomy: nil)
    }

    func matches(_ w: Workout, taxonomy: Taxonomy?) -> Bool {
        if !durations.isEmpty && !durations.contains(w.durationBucket) { return false }
        if !trainers.isEmpty && !trainers.contains(w.trainer) { return false }
        if !bodyFocus.isEmpty && !bodyFocus.contains(w.facets.bodyFocus) { return false }
        if !muscleGroups.isEmpty && muscleGroups.isDisjoint(with: w.facets.muscleGroups) { return false }
        if !equipment.isEmpty && equipment.isDisjoint(with: w.facets.equipment) { return false }
        if !matchesDumbbellLoad(w.facets.dumbbellLoad) { return false }
        let q = search.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            // Search matches only by episode number, as a prefix so "2" hits
            // episodes 2, 20, 21, 202, … Workouts without an episode never match.
            guard let episode = w.episode,
                  String(episode).hasPrefix(q) else { return false }
        }
        return true
    }

    mutating func toggle<T: Hashable>(_ value: T, in keyPath: WritableKeyPath<WorkoutFilter, Set<T>>) {
        if self[keyPath: keyPath].contains(value) { self[keyPath: keyPath].remove(value) }
        else { self[keyPath: keyPath].insert(value) }
    }

    mutating func toggleEquipment(_ slug: String) {
        if equipment.contains(slug) {
            equipment.remove(slug)
        } else if slug == "no-equipment" {
            equipment = ["no-equipment"]
        } else {
            equipment.insert(slug)
            equipment.remove("no-equipment")
        }

        if !equipment.contains("dumbbells") {
            dumbbellLoad = []
        }
    }

    mutating func toggleDumbbellLoad(_ slug: String) {
        if dumbbellLoad.contains(slug) {
            dumbbellLoad.remove(slug)
        } else {
            dumbbellLoad.insert(slug)
        }

        if ["light", "medium", "heavy"].contains(slug) {
            equipment.insert("dumbbells")
            equipment.remove("no-equipment")
        }
    }

    mutating func clearFacets() {
        durations = []; trainers = []; bodyFocus = []
        muscleGroups = []; equipment = []; dumbbellLoad = []
    }

    private func matchesDumbbellLoad(_ workoutLoad: [String]?) -> Bool {
        guard !dumbbellLoad.isEmpty else { return true }
        guard let workoutLoad else { return false }

        let selectedWeighted = dumbbellLoad.subtracting(["bodyweight"])
        let workoutWeighted = Set(workoutLoad).subtracting(["bodyweight"])

        if selectedWeighted.isEmpty {
            return workoutWeighted.isEmpty && workoutLoad.contains("bodyweight")
        }

        // Bodyweight-only workouts are a convenience fallback for a bare
        // dumbbell-tier search. Once the user explicitly scopes Equipment to
        // Dumbbells, the tier acts as a refinement of dumbbell workouts only.
        if equipment.isEmpty && workoutWeighted.isEmpty {
            return workoutLoad.contains("bodyweight")
        }

        return workoutWeighted == selectedWeighted
    }
}
