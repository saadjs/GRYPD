import Foundation

/// Thin index describing the published, content-addressed catalog files.
struct Manifest: Codable {
    let schemaVersion: Int
    let generatedAt: String
    let catalogVersion: String
    let taxonomy: FileRef
    let disciplines: [DisciplineRef]

    func discipline(_ slug: String) -> DisciplineRef? {
        disciplines.first { $0.slug == slug }
    }
}

struct FileRef: Codable {
    let file: String
    let sha256_10: String
    let bytes: Int
}

struct DisciplineRef: Codable {
    let slug: String
    let label: String
    let file: String
    let sha256_10: String
    let count: Int
    let bytes: Int
}
