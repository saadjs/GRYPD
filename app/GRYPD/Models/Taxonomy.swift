import Foundation

/// slug -> human label maps, decoded from `taxonomy.json`.
struct Taxonomy: Codable {
    let bodyFocus: [String: String]
    let muscleGroups: [String: String]
    let equipment: [String: String]
    let dumbbells: [String: String]
    let trainers: [String: String]
    let moves: [String: String]
    let disciplines: [String: String]

    static let empty = Taxonomy(bodyFocus: [:], muscleGroups: [:], equipment: [:],
                                dumbbells: [:], trainers: [:], moves: [:], disciplines: [:])

    private static func label(_ dict: [String: String], _ slug: String) -> String {
        dict[slug] ?? slug.replacingOccurrences(of: "-", with: " ").capitalized
    }

    /// Display overrides for equipment labels that read better in the UI than the
    /// harvested source label (e.g. "No Equipment" → "None"). Applied at display
    /// time so it survives pipeline regeneration of `taxonomy.json`.
    private static let equipmentDisplayOverrides = ["no-equipment": "None"]
    private static func equipmentDisplay(_ slug: String, _ dict: [String: String]) -> String {
        equipmentDisplayOverrides[slug] ?? label(dict, slug)
    }

    func trainer(_ s: String) -> String { Self.label(trainers, s) }
    func bodyFocus(_ s: String) -> String { Self.label(bodyFocus, s) }
    func muscle(_ s: String) -> String { Self.label(muscleGroups, s) }
    func equipmentLabel(_ s: String) -> String { Self.equipmentDisplay(s, equipment) }
    func move(_ s: String) -> String { Self.label(moves, s) }

    /// Muscle-group slugs sorted by their label — for the filter UI.
    var muscleGroupsSorted: [(slug: String, label: String)] {
        muscleGroups.map { ($0.key, $0.value) }.sorted { $0.1 < $1.1 }
    }
    var trainersSorted: [(slug: String, label: String)] {
        trainers.map { ($0.key, $0.value) }.sorted { $0.1 < $1.1 }
    }
    var equipmentSorted: [(slug: String, label: String)] {
        equipment.map { ($0.key, Self.equipmentDisplay($0.key, equipment)) }.sorted { $0.1 < $1.1 }
    }
}
