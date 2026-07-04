import Foundation

/// Which metric a mode of the detail chart is showing. Intensity answers "how hard
/// was the hardest set" (est. max / best reps / longest hold); volume answers "how
/// much total work" (tonnage / total reps / total time).
enum MetricMode: String, CaseIterable, Identifiable {
    case intensity
    case volume
    var id: String { rawValue }
}

/// The yardstick a move is tracked by. **Strength-only for now** — this is the one
/// seam where a new metric type would slot in: add a case, fill the switches, and
/// nothing else in Progress has to change. Each kind yields two numbers per session,
/// an *intensity* (top set on this scale) and a *volume* (total work across sets).
///
/// A move's kind is inferred from what the user actually logged (see `classify`) —
/// the catalog carries no per-move type, and inference stays correct when a lifter
/// loads a normally-bodyweight move or does a loaded move unweighted.
enum MetricKind: String, Codable {
    case weighted     // loaded move → est. one-rep max / tonnage
    case bodyweight   // reps-only move → best-set reps / total reps
    case timed        // isometric hold → longest hold / total time

    /// A move's kind follows its *latest* session's top set: once you start loading
    /// a move it reads as weighted from then on. The weight → reps → seconds
    /// precedence mirrors `MoveEntry.topSet`'s own ranking.
    static func classify(topSet: SetEntry) -> MetricKind {
        if topSet.weightValue > 0 { return .weighted }
        if (topSet.reps ?? 0) > 0 { return .bodyweight }
        return .timed
    }

    // MARK: - Values

    /// Epley estimated one-rep max. Missing/zero reps floor to 1 (a logged weight
    /// always counts as at least a single); reps clamp at 12 because the estimate
    /// turns to fiction past there — an unclamped 30-rep set would spike the
    /// strength line into a PR that never happened. Raw reps still feed `volume`.
    static func estimatedOneRepMax(weight: Double, reps: Int?) -> Double {
        let effectiveReps = min(max(reps ?? 1, 1), 12)
        return weight * (1 + Double(effectiveReps) / 30)
    }

    /// One set's intensity on this kind's scale. Weight is pre-converted to the
    /// display unit so est. max reads in the user's unit.
    func intensity(of set: SetEntry, displayUnit: WeightUnit) -> Double {
        switch self {
        case .weighted:
            let weight = set.weightUnit.convertedWeight(set.weightValue, to: displayUnit)
            return Self.estimatedOneRepMax(weight: weight, reps: set.reps)
        case .bodyweight:
            return Double(max(set.reps ?? 0, 0))
        case .timed:
            return Double(max(set.seconds ?? 0, 0))
        }
    }

    /// The set that defines the session's intensity: the argmax of `intensity(of:)`
    /// across every set. For weighted this is the highest *estimated* one-rep max,
    /// which can be a lighter, higher-rep set (100×12 ≈ 140 beats a 110×1 single
    /// ≈ 114) — deliberately **not** the heaviest raw weight that `MoveEntry.topSet`
    /// ranks by, since that would chart the lower estimate. For bodyweight/timed it
    /// coincides with `topSet` (both pick the most reps / longest hold).
    func peakSet(in sets: [SetEntry], displayUnit: WeightUnit) -> SetEntry? {
        sets.max { intensity(of: $0, displayUnit: displayUnit) < intensity(of: $1, displayUnit: displayUnit) }
    }

    /// Total work across every set in the session. For weighted, missing reps count
    /// as 1 (matching the est.-max floor) so a weight-only log contributes its weight
    /// rather than vanishing to a zero-volume session.
    func volume(sets: [SetEntry], displayUnit: WeightUnit) -> Double {
        switch self {
        case .weighted:
            return sets.reduce(0) { sum, set in
                let weight = set.weightUnit.convertedWeight(set.weightValue, to: displayUnit)
                return sum + weight * Double(max(set.reps ?? 1, 1))
            }
        case .bodyweight:
            return sets.reduce(0) { $0 + Double(max($1.reps ?? 0, 0)) }
        case .timed:
            return sets.reduce(0) { $0 + Double(max($1.seconds ?? 0, 0)) }
        }
    }

    // MARK: - Labels

    /// Headline qualifier under the big number on a card/hero. Weighted spells out
    /// "1-rep max" in parens so the computed est. max never reads as a lifted weight.
    var intensityLabel: String {
        switch self {
        case .weighted: return "est. max (1-rep max)"
        case .bodyweight: return "best set"
        case .timed: return "best hold"
        }
    }

    /// Titles for the detail view's segmented Est.-Max/Volume toggle.
    func segmentTitle(_ mode: MetricMode) -> String {
        switch (self, mode) {
        case (.weighted, .intensity):   return "Est. Max"
        case (.bodyweight, .intensity): return "Best Set"
        case (.timed, .intensity):      return "Best Hold"
        case (.weighted, .volume):      return "Volume"
        case (.bodyweight, .volume):    return "Total Reps"
        case (.timed, .volume):         return "Total Time"
        }
    }

    /// The number, formatted for its scale: weight rounds via the shared helper,
    /// reps are whole, time renders as m:ss (or `Ns` under a minute). Intensity and
    /// volume share a scale within a kind, so `mode` doesn't change the format.
    func valueText(_ value: Double) -> String {
        switch self {
        case .weighted: return formatted(value)
        case .bodyweight: return String(Int(value.rounded()))
        case .timed: return Self.timeText(Int(value.rounded()))
        }
    }

    /// Trailing unit chip after the number, or `nil` when the value already reads as
    /// its own unit (timed values are self-describing as m:ss / Ns).
    func unitText(weightUnit: WeightUnit) -> String? {
        switch self {
        case .weighted: return weightUnit.label
        case .bodyweight: return "reps"
        case .timed: return nil
        }
    }

    /// Signed change in this kind's units, e.g. "+12 lb", "+3 reps", "+0:15". The
    /// weight unit is passed through so kg users see kg (weighted only; other kinds
    /// ignore it).
    func deltaText(_ delta: Double, weightUnit: WeightUnit) -> String {
        let sign = delta >= 0 ? "+" : "-"
        let magnitude = valueText(abs(delta))
        if let unit = unitText(weightUnit: weightUnit) {
            return "\(sign)\(magnitude) \(unit)"
        }
        return "\(sign)\(magnitude)"
    }

    static func timeText(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
