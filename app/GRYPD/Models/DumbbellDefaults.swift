import Foundation

/// The three dumbbell "weight buckets" a lifter typically owns. Fitness+ prescribes
/// moves by relative heaviness (light / medium / heavy) rather than an absolute load,
/// so we map each catalog move to a bucket and auto-fill the user's configured weight
/// for that bucket when logging. See `DumbbellDefaults`.
enum DumbbellTier: String, CaseIterable, Identifiable {
    case light, medium, heavy
    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    /// Best-judgement bucket for a catalog move slug, or `nil` for moves that are
    /// bodyweight (or don't take a fixed dumbbell load) and so shouldn't auto-fill.
    ///
    /// - **Heavy:** compound lower-body and heavy horizontal push/pull — squats,
    ///   lunges, hinges, swings, chest press, rows.
    /// - **Medium:** overhead/standing presses, curls, and rotational power moves —
    ///   shoulder press, upright row, clean, snatch, halo, chop.
    /// - **Light:** shoulder/arm isolation — lateral & front raises, rear-delt work,
    ///   triceps extensions, flyes, rotator-cuff moves.
    static func classify(_ slug: String) -> DumbbellTier? {
        if heavySlugs.contains(slug) { return .heavy }
        if mediumSlugs.contains(slug) { return .medium }
        if lightSlugs.contains(slug) { return .light }
        return nil
    }

    private static let heavySlugs: Set<String> = [
        "squat", "lunge", "lateral-lunge", "curtsy", "plie", "stepback",
        "stepback-hinge", "single-leg-squat", "single-leg-hinge", "pistol-squat",
        "kneel-to-squat", "kneel-to-split-squat", "hinge", "hinge-and-swing",
        "swing", "chest-press", "row", "pull-through", "sweep", "shovel",
    ]

    private static let mediumSlugs: Set<String> = [
        "overhead-press", "forward-press", "server-press", "standing-chest-press",
        "curl", "upright-row", "high-pull", "clean", "snatch", "halo", "palm-press",
        "svend-press", "serve", "juggler", "chop", "diagonal-lift",
        "diagonal-punch-up", "windmill", "reach", "punch", "dumbbell-pass",
        "thoracic-rotation",
    ]

    private static let lightSlugs: Set<String> = [
        "lateral-raise", "front-raise", "rear-delt-raise", "reverse-fly",
        "chest-fly", "w-flye", "tricep-extension", "skullcrusher", "tate-press",
        "kickback", "y-raise", "l-raise", "iyt-raise", "circular-raise",
        "poliquin-raise", "powell-raise", "snow-angel", "prone-w",
        "scapular-retraction", "face-pull", "external-shoulder-rotation",
        "internal-shoulder-rotation", "around-the-world-shoulder-rotation",
        "rainbow-arc", "arm-circles",
    ]
}

/// The user's configured default dumbbell weights, expressed in `unit`. Persisted in
/// `UserDefaults` (see the `key…` constants) and read on the log screen to auto-fill a
/// move's weight from its `DumbbellTier`.
struct DumbbellDefaults: Equatable {
    var light: Double
    var medium: Double
    var heavy: Double
    var unit: WeightUnit

    static let keyLight = "dumbbellLight"
    static let keyMedium = "dumbbellMedium"
    static let keyHeavy = "dumbbellHeavy"

    /// Starting values (lb): light 10, medium 15, heavy 25 — the low end of the
    /// user's typical raises / shoulder-press / squat loads.
    static let defaultLight: Double = 10
    static let defaultMedium: Double = 15
    static let defaultHeavy: Double = 25

    func weight(for tier: DumbbellTier) -> Double {
        switch tier {
        case .light: return light
        case .medium: return medium
        case .heavy: return heavy
        }
    }

    /// Auto-fill weight for a catalog move slug, or `nil` for bodyweight moves.
    func weight(forMoveSlug slug: String?) -> Double? {
        guard let slug, let tier = DumbbellTier.classify(slug) else { return nil }
        return weight(for: tier)
    }

    // MARK: - Picker options

    /// Selectable dumbbell weights for the settings picker, granular enough to feel
    /// like "any weight" while staying a tidy menu.
    static func options(for unit: WeightUnit) -> [Double] {
        switch unit {
        case .lb: return Array(stride(from: 2.5, through: 120, by: 2.5))
        case .kg: return Array(stride(from: 1, through: 60, by: 1))
        }
    }

    static func nearestOption(_ value: Double, for unit: WeightUnit) -> Double {
        options(for: unit).min { abs($0 - value) < abs($1 - value) } ?? value
    }

    /// "25 lb" / "12.5 kg" — integer when whole, one decimal otherwise.
    static func format(_ weight: Double, unit: WeightUnit) -> String {
        let number = weight.rounded() == weight
            ? String(Int(weight))
            : String(format: "%.1f", weight)
        return "\(number) \(unit.label)"
    }
}
