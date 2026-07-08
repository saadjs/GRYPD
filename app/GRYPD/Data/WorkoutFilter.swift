import Foundation

/// Pure in-memory filter over the catalog. Instant at 531 objects.
struct WorkoutFilter: Equatable {
    var search: String = ""
    var durations: Set<Int> = []        // buckets: 10, 20, 30
    var trainers: Set<String> = []      // slugs
    var bodyFocus: Set<String> = []     // slugs
    var muscleGroups: Set<String> = []  // slugs (match ANY)
    var equipment: Set<String> = []     // slugs (match ANY)
    var dumbbellLoad: Set<String> = []  // light/medium/heavy/bodyweight (match ANY)

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
        if !dumbbellLoad.isEmpty && dumbbellLoad.isDisjoint(with: w.facets.dumbbellLoad ?? []) { return false }
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

    mutating func clearFacets() {
        durations = []; trainers = []; bodyFocus = []
        muscleGroups = []; equipment = []; dumbbellLoad = []
    }
}
