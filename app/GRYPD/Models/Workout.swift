import Foundation

/// A strength workout from the prebuilt catalog. Decoded from `strength.json`.
/// `moveSequence` and `coachNotes` are optional for forward-compatibility with a
/// richer pipeline output; the current data has `moves` only.
struct Workout: Codable, Identifiable, Hashable {
    let id: String              // stable Apple adam id — the join key for logs
    let aliases: [String]?      // prior catalog ids that should still join to this workout
    let discipline: String
    let title: String
    let trainer: String         // slug -> taxonomy label
    let durationMinutes: Int
    let episode: Int?
    let appleUrl: String?
    let summary: String?
    let releaseDate: String?     // ISO "YYYY-MM-DD" from Apple
    let facets: Facets
    let moves: [String]
    let moveSequence: [String]?
    let coachNotes: String?

    enum CodingKeys: String, CodingKey {
        case id, aliases, discipline, title, trainer, durationMinutes, episode
        case appleUrl
        case summary = "description"
        case releaseDate
        case facets, moves, moveSequence, coachNotes
    }

    init(id: String,
         aliases: [String]? = nil,
         discipline: String,
         title: String,
         trainer: String,
         durationMinutes: Int,
         episode: Int?,
         appleUrl: String?,
         summary: String?,
         releaseDate: String?,
         facets: Facets,
         moves: [String],
         moveSequence: [String]?,
         coachNotes: String?) {
        self.id = id
        self.aliases = aliases
        self.discipline = discipline
        self.title = title
        self.trainer = trainer
        self.durationMinutes = durationMinutes
        self.episode = episode
        self.appleUrl = appleUrl
        self.summary = summary
        self.releaseDate = releaseDate
        self.facets = facets
        self.moves = moves
        self.moveSequence = moveSequence
        self.coachNotes = coachNotes
    }
}

struct Facets: Codable, Hashable {
    let bodyFocus: String
    let muscleGroups: [String]
    let equipment: [String]
    let dumbbells: [String]?
}

extension Workout {
    var appleURL: URL? {
        guard let appleUrl else { return nil }
        return URL(string: appleUrl)
    }

    /// Newest Apple Fitness+ release first, with stable fallbacks for missing dates.
    static func newestFirst(_ lhs: Workout, _ rhs: Workout) -> Bool {
        switch (lhs.releaseDate, rhs.releaseDate) {
        case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
            return lhsDate > rhsDate
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            break
        }

        switch (Int(lhs.id), Int(rhs.id)) {
        case let (lhsID?, rhsID?) where lhsID != rhsID:
            return lhsID > rhsID
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            let titleOrder = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
            if titleOrder != .orderedSame {
                return titleOrder == .orderedAscending
            }
            return lhs.id > rhs.id
        }
    }

    /// Duration bucket used for filtering (11 -> 10, 21 -> 20, 31 -> 30).
    var durationBucket: Int { Int((Double(durationMinutes) / 10).rounded()) * 10 }
    var durationLabel: String { "\(durationBucket) min" }

    /// Ordered move list if available, else the (unordered) move tags.
    var displayMoves: [String] { moveSequence ?? moves }

    /// "Jun 29, 2026" from the ISO release date, or nil if unavailable/unparseable.
    var releaseDateLabel: String? {
        guard let releaseDate else { return nil }
        guard let date = Self.isoDay.date(from: releaseDate) else { return nil }
        return Self.display.string(from: date)
    }

    /// Month start (UTC) parsed from the ISO release date, for month grouping.
    var releaseMonthStart: Date? {
        guard let releaseDate else { return nil }
        guard let day = Self.isoDay.date(from: releaseDate) else { return nil }
        return Self.monthCal.dateInterval(of: .month, for: day)?.start
    }

    private static let monthCal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return c
    }()

    private static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let display: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "MMM d, yyyy"
        return f
    }()
}

// MARK: - Month grouping

/// A month bucket of workouts, newest month first. Mirrors the History screen's
/// `HistoryStats.byMonth` shape (id + label + items) so Browse renders the same
/// "JUNE 2026" section headings. Months with zero matching workouts are omitted
/// by construction (only months present in the input appear).
struct WorkoutMonth: Identifiable, Hashable {
    let id: Date                  // month start (UTC)
    let label: String             // "JUNE 2026"
    let workouts: [Workout]
}

extension Array where Element == Workout {
    /// Group workouts by calendar month, newest month first, each group's
    /// workouts newest first. Workouts without a parseable release date are
    /// dropped (the catalog always has dates).
    func byMonth() -> [WorkoutMonth] {
        let grouped = Dictionary(grouping: self.compactMap { w -> (Date, Workout)? in
            guard let month = w.releaseMonthStart else { return nil }
            return (month, w)
        }, by: { $0.0 })
        return grouped.map { (month, pairs) in
            WorkoutMonth(
                id: month,
                label: month.formatted(.dateTime.month(.wide).year()).uppercased(),
                workouts: pairs.map { $0.1 }.sorted(by: Workout.newestFirst))
        }.sorted { $0.id > $1.id }
    }
}
