#if DEBUG
import Foundation
import SwiftData

/// Developer-only fixture generator: fills the log store with a realistic spread
/// of sessions so History and Progression have something to show. Compiled out
/// of release builds entirely (`#if DEBUG`). Deterministic (fixed seed) so the
/// demo looks the same every time.
@MainActor
enum SampleData {

    /// How far back the fixture reaches. Two years so the 1M/3M/6M/All ranges each
    /// show a different slice and progression can be read across weeks, months, and
    /// year boundaries.
    static let historyMonths = 24

    /// Replace any existing logs with ~2 years of varied sessions spanning all three
    /// metric kinds (weighted, bodyweight-reps, timed holds).
    static func seed(context: ModelContext, catalog: CatalogStore) {
        clear(context: context)

        let roster = pickRoster(from: catalog.workouts)
        guard !roster.isEmpty else { return }

        let cal = Calendar(identifier: .gregorian)
        let today = Date.now
        guard let start = cal.date(byAdding: .month, value: -historyMonths, to: cal.startOfDay(for: today)) else { return }

        var rng = SeededGenerator(seed: 42)
        var pick = 0

        // Walk week by week from the start to now, logging 2–4 sessions/week.
        var weekStart = start
        while weekStart < today {
            let perWeek = Int.random(in: 2...4, using: &rng)
            var usedDays = Set<Int>()
            for _ in 0..<perWeek {
                let dayOffset = uniqueDay(&usedDays, &rng)
                let hour = Int.random(in: 6...20, using: &rng)
                let minute = Int.random(in: 0...59, using: &rng)
                guard let day = cal.date(byAdding: .day, value: dayOffset, to: weekStart),
                      let when = cal.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                      when <= today else { continue }

                let workout = roster[pick % roster.count]; pick += 1
                let progress = clamp01(when.timeIntervalSince(start) / today.timeIntervalSince(start))
                insertSession(workout, at: when, progress: progress,
                              context: context, catalog: catalog, rng: &rng)
            }
            guard let next = cal.date(byAdding: .weekOfYear, value: 1, to: weekStart) else { break }
            weekStart = next
        }

        try? context.save()
    }

    /// Delete every logged session (cascades to move entries).
    static func clear(context: ModelContext) {
        try? context.delete(model: WorkoutLog.self)
        try? context.save()
    }

    // MARK: - Building blocks

    /// Up to three distinct-trainer workouts per body focus, so the demo spans
    /// trainers, durations, and all three focus colors.
    private static func pickRoster(from workouts: [Workout]) -> [Workout] {
        var roster: [Workout] = []
        for focus in ["upper-body", "lower-body", "total-body"] {
            var seen = Set<String>()
            for w in workouts where w.facets.bodyFocus == focus {
                if seen.insert(w.trainer).inserted { roster.append(w) }
                if seen.count == 3 { break }
            }
        }
        return roster.isEmpty ? Array(workouts.prefix(6)) : roster
    }

    private static func insertSession(_ workout: Workout, at when: Date, progress: Double,
                                      context: ModelContext, catalog: CatalogStore,
                                      rng: inout SeededGenerator) {
        let log = WorkoutLog(workoutId: workout.id, performedAt: when,
                             note: note(progress: progress, rng: &rng))
        // ~1 in 2 sessions carries a hand-entered calorie estimate so the new
        // Metrics tile on the detail screen has demo data.
        if Int.random(in: 0...1, using: &rng) == 0 {
            log.activeEnergyKcal = Double(Int.random(in: 150...420, using: &rng))
        }
        context.insert(log)

        for slug in workout.displayMoves {
            let kind = sampleKind(for: slug)

            let entry = MoveEntry(moveSlug: slug, label: catalog.taxonomy.move(slug))
            entry.log = log
            log.moveEntries.append(entry)
            context.insert(entry)

            let setCount = Int.random(in: 2...4, using: &rng)
            for setIndex in 0..<setCount {
                let set = makeSet(kind: kind, slug: slug, setIndex: setIndex,
                                  progress: progress, rng: &rng)
                set.moveEntry = entry
                entry.sets.append(set)
                context.insert(set)
            }
        }
    }

    /// One set on the move's own scale. Every kind climbs its relevant dimension
    /// over the fixture's span (weight / reps / hold time) with light jitter, and
    /// the top set lands first so `MoveEntry.topSet` picks a stable session best.
    private static func makeSet(kind: SampleKind, slug: String, setIndex: Int,
                                progress: Double, rng: inout SeededGenerator) -> SetEntry {
        switch kind {
        case .weighted:
            let jitter = Double(Int.random(in: -1...1, using: &rng)) * 2.5
            let raw = baseWeight(for: slug) + progress * 20 + jitter
            // Later sets a touch heavier, so the last set is the day's top set.
            let weight = max(5, (raw / 5).rounded() * 5) + Double(setIndex) * 2.5
            let reps = Int.random(in: 8...12, using: &rng)
            return SetEntry(order: setIndex, weightValue: weight, weightUnit: .lb,
                            reps: reps, seconds: nil)
        case .bodyweight:
            let jitter = Int.random(in: -1...1, using: &rng)
            // Reps climb over time; later sets drop off with fatigue (first = best).
            let reps = max(3, baseReps(for: slug) + Int((progress * 12).rounded()) + jitter - setIndex)
            return SetEntry(order: setIndex, weightValue: 0, reps: reps, seconds: nil)
        case .timed:
            let jitter = Int.random(in: -3...3, using: &rng)
            let seconds = max(10, baseSeconds(for: slug) + Int((progress * 60).rounded()) + jitter - setIndex * 3)
            return SetEntry(order: setIndex, weightValue: 0, reps: nil, seconds: seconds)
        }
    }

    /// The metric kind a move is seeded as. Stable per slug (so a move keeps one
    /// kind across its whole history) and biased toward weighted, but the hash
    /// fallback guarantees some bodyweight and timed moves appear no matter what
    /// the catalog's move names are — so all three Progress paths get exercised.
    private enum SampleKind { case weighted, bodyweight, timed }

    private static func sampleKind(for slug: String) -> SampleKind {
        let s = slug.lowercased()
        let timedHints = ["plank", "hold", "wall-sit", "hollow", "dead-hang", "l-sit", "superman", "carry", "isometric"]
        let bodyweightHints = ["push-up", "pushup", "pull-up", "pullup", "sit-up", "situp",
                               "crunch", "burpee", "mountain-climber", "climber", "jumping-jack",
                               "air-squat", "dip", "glute-bridge", "bird-dog"]
        if timedHints.contains(where: s.contains) { return .timed }
        if bodyweightHints.contains(where: s.contains) { return .bodyweight }
        switch hash(slug) % 6 {
        case 0: return .timed
        case 1: return .bodyweight
        default: return .weighted
        }
    }

    /// Deterministic starting weight per move slug, 10–45 lb in 5 lb steps.
    private static func baseWeight(for slug: String) -> Double {
        10 + Double(hash(slug) % 8) * 5
    }

    /// Deterministic starting reps (8–14) and hold seconds (20–40) per move slug.
    private static func baseReps(for slug: String) -> Int { 8 + Int(hash(slug) % 7) }
    private static func baseSeconds(for slug: String) -> Int { 20 + Int(hash(slug) % 5) * 5 }

    /// FNV-1a over the slug — a stable per-move seed for the deterministic bases.
    private static func hash(_ slug: String) -> UInt64 {
        var h: UInt64 = 1469598103934665603
        for b in slug.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return h
    }

    private static let notes = [
        "Felt strong today.", "Tough one — dropped the last set.",
        "New PR on the presses.", "Short on time, kept it moving.",
        "Legs were smoked afterward.", "Great pump.",
    ]

    private static func note(progress: Double, rng: inout SeededGenerator) -> String? {
        // ~1 in 3 sessions gets a note.
        Int.random(in: 0...2, using: &rng) == 0 ? notes.randomElement(using: &rng) : nil
    }

    private static func uniqueDay(_ used: inout Set<Int>, _ rng: inout SeededGenerator) -> Int {
        for _ in 0..<8 {
            let d = Int.random(in: 0...6, using: &rng)
            if used.insert(d).inserted { return d }
        }
        return Int.random(in: 0...6, using: &rng)
    }

    private static func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }
}

/// Tiny deterministic RNG (SplitMix64) so the fixture is identical every run.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
#endif
