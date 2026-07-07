import Foundation
import SwiftData

/// A user-created exercise, stored user-side because `taxonomy.json` is replaced
/// wholesale on every catalog refresh and can't hold user data.
///
/// The `slug` is generated with the *exact same* rule the pipeline uses to slug
/// catalog moves (see `pipeline/common.py: slugify`), so a custom `hammer-curl`
/// and a future catalog `hammer-curl` share one identity: logged history keys on
/// the slug string, so progression merges automatically and the now-redundant
/// `CustomMove` is pruned by `CustomMoveStore.reconcile` on the next catalog load.
@Model
final class CustomMove {
    /// Pipeline-compatible slug; the stable identity logged sets group by.
    var slug: String = ""
    /// Human label shown in the picker and copied onto each logged `MoveEntry`.
    var label: String = ""
    var createdAt: Date = Date.now

    init(slug: String, label: String, createdAt: Date = .now) {
        self.slug = slug
        self.label = label
        self.createdAt = createdAt
    }

    /// Port of `pipeline/common.py: slugify` — lowercase, collapse every run of
    /// non-`[a-z0-9]` to a single dash, trim leading/trailing dashes. Returns ""
    /// for input with no alphanumerics (callers must reject an empty slug).
    static func slug(from label: String) -> String {
        let replaced = label.lowercased().replacing(/[^a-z0-9]+/, with: "-")
        return replaced.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

enum CustomMoveStore {
    /// Prune custom moves the catalog has since absorbed: once a slug exists in the
    /// taxonomy, the catalog entry owns it (picker shows one row, its label wins),
    /// and logged history is untouched because it keys on the slug string, not the
    /// `CustomMove` record. Safe to run on every catalog load.
    @MainActor
    static func reconcile(context: ModelContext, catalogSlugs: Set<String>) {
        guard !catalogSlugs.isEmpty else { return }
        let all = (try? context.fetch(FetchDescriptor<CustomMove>())) ?? []
        var changed = false
        for move in all where catalogSlugs.contains(move.slug) {
            context.delete(move)
            changed = true
        }
        if changed { try? context.save() }
    }
}
