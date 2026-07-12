import Foundation
import Observation

/// In-memory, replaceable catalog. Loads a bundled snapshot at launch (offline-first),
/// then can refresh from a remote manifest, downloading only changed content-addressed files.
/// This is deliberately NOT persisted in SwiftData — it is disposable and version-swapped.
@MainActor
@Observable
final class CatalogStore {
    private(set) var workouts: [Workout] = []
    private(set) var taxonomy: Taxonomy = .empty
    private(set) var catalogVersion: String = "—"
    private(set) var generatedAt: Date?
    private(set) var lastRefreshed: Date?
    private(set) var isRefreshing = false

    /// Cloudflare R2 base URL that serves manifest.json + content-addressed files.
    /// Remote refresh stays silent until the custom domain resolves and serves valid JSON.
    var remoteBaseURL: URL? = URL(string: "https://grypd.saad.sh")

    private var index: [String: Workout] = [:]

    init() { loadBundled() }

    init(workouts: [Workout], taxonomy: Taxonomy = .empty) {
        self.taxonomy = taxonomy
        setWorkouts(workouts)
    }

    func workout(id: String) -> Workout? { index[id] }

    func bodyFocus(for workoutId: String) -> WorkoutBodyFocus? {
        workout(id: workoutId).flatMap { WorkoutBodyFocus(rawValue: $0.facets.bodyFocus) }
    }

    func canonicalWorkoutId(for id: String) -> String? {
        workout(id: id)?.id
    }

    func log(_ log: WorkoutLog, belongsTo workout: Workout) -> Bool {
        canonicalWorkoutId(for: log.workoutId) == workout.id
    }

    func filtered(_ f: WorkoutFilter) -> [Workout] {
        f.isEmpty ? workouts : workouts.filter { f.matches($0, taxonomy: taxonomy) }
    }

    // MARK: - Bundled load

    private func loadBundled() {
        if let m: Manifest = Self.decodeBundle("manifest") {
            catalogVersion = m.catalogVersion
            generatedAt = Self.parseGeneratedAt(m.generatedAt)
        }
        if let t: Taxonomy = Self.decodeBundle("taxonomy") { taxonomy = t }
        if let w: [Workout] = Self.decodeBundle("strength") { setWorkouts(w) }
    }

    private func setWorkouts(_ w: [Workout]) {
        workouts = w.sorted(by: Workout.newestFirst)
        index = workouts.reduce(into: [:]) { out, workout in
            out[workout.id] = workout
            for alias in workout.aliases ?? [] where out[alias] == nil {
                out[alias] = workout
            }
        }
    }

    static func decodeBundle<T: Decodable>(_ name: String) -> T? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static let iso8601Formatter = ISO8601DateFormatter()

    static func parseGeneratedAt(_ string: String) -> Date? {
        iso8601Formatter.date(from: string)
    }

    // MARK: - Remote refresh (manifest diff, changed files only)

    /// Fetch the manifest; if the strength file's hash changed, download & swap it.
    /// Cached to Application Support so subsequent launches use the newest good copy.
    func refresh() async {
        guard let base = remoteBaseURL, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let manifest: Manifest = try await Self.fetchJSON(base.appendingPathComponent("manifest.json"))
            guard let disc = manifest.discipline("strength") else { return }

            if manifest.taxonomy.sha256_10 != cachedHash("taxonomy") {
                let t: Taxonomy = try await Self.fetchJSON(base.appendingPathComponent(manifest.taxonomy.file))
                taxonomy = t
                cache(t, "taxonomy", hash: manifest.taxonomy.sha256_10)
            }
            if disc.sha256_10 != cachedHash("strength") {
                let w: [Workout] = try await Self.fetchJSON(base.appendingPathComponent(disc.file))
                setWorkouts(w)
                cache(w, "strength", hash: disc.sha256_10)
            }
            catalogVersion = manifest.catalogVersion
            generatedAt = Self.parseGeneratedAt(manifest.generatedAt)
            lastRefreshed = .now
        } catch {
            // Network/parse failure: keep last-known-good silently.
        }
    }

    private static func fetchJSON<T: Decodable>(_ url: URL) async throws -> T {
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Disk cache

    private static var cacheDir: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("catalog", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private func cachedHash(_ name: String) -> String? {
        try? String(contentsOf: Self.cacheDir.appendingPathComponent("\(name).hash"), encoding: .utf8)
    }
    private func cache<T: Encodable>(_ value: T, _ name: String, hash: String) {
        if let data = try? JSONEncoder().encode(value) {
            try? data.write(to: Self.cacheDir.appendingPathComponent("\(name).json"))
            try? hash.write(to: Self.cacheDir.appendingPathComponent("\(name).hash"), atomically: true, encoding: .utf8)
        }
    }
}
