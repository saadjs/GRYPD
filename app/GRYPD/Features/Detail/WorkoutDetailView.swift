import SwiftUI
import SwiftData

/// Workout detail modeled on the Apple Fitness+ episode screen: a full-bleed hero
/// with the title overlaid, a green trainer name, two compact meta lines
/// (duration · episode · release date, then equipment · body focus), a primary
/// "Let's Go" action, an expandable description, and the granular moves + history
/// this companion app adds on top. (No Music section — we don't have that data.)
struct WorkoutDetailView: View {
    let workout: Workout
    @Environment(CatalogStore.self) private var catalog
    @Environment(\.openURL) private var openURL
    @State private var showLog = false
    @State private var descExpanded = false

    // Reactively refresh when logs change.
    @Query private var allLogs: [WorkoutLog]
    private var sessions: [WorkoutLog] {
        allLogs.filter { catalog.log($0, belongsTo: workout) }
            .sorted { $0.performedAt > $1.performedAt }
    }

    private var tax: Taxonomy { catalog.taxonomy }

    var body: some View {
        HeroDetailLayout {
            DetailHero(workout: workout) {
                Text(workout.title)
                    .heroTitleFont()
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } controls: {
            Button { showLog = true } label: { Image(systemName: "plus") }
            if let url = workout.appleURL {
                Menu {
                    Button {
                        openURL(url)
                    } label: {
                        Label("Open in Apple Fitness+", systemImage: "arrow.up.forward.app")
                    }
                    ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        } content: {
            meta
            actions
            description
            muscleGroups
            movesSection
            historySection
        }
        .sheet(isPresented: $showLog) {
            LogSessionView(workout: workout)
        }
    }

    // MARK: Meta

    private var meta: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tax.trainer(workout.trainer))
                .scaledFont(22, weight: .bold, relativeTo: .title2)
                .foregroundStyle(Color.brand)

            Text(dotJoined(metaLine1))
                .primaryLabelFont()
                .foregroundStyle(.white)
            if !metaLine2.isEmpty {
                Text(dotJoined(metaLine2))
                    .primaryLabelFont()
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardSurface(radius: AppRadius.panel)
    }

    private var metaLine1: [String] {
        var parts = ["\(workout.durationMinutes)min"]
        if let ep = workout.episode { parts.append("Ep\(ep)") }
        if let released = workout.releaseDateLabel { parts.append(released) }
        return parts
    }

    private var metaLine2: [String] {
        workout.facets.equipment.map { tax.equipmentLabel($0) }
            + [tax.bodyFocus(workout.facets.bodyFocus)]
    }

    private func dotJoined(_ parts: [String]) -> String {
        parts.joined(separator: "  •  ")
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 12) {
            if let url = workout.appleURL {
                Button { openURL(url) } label: {
                    Text("Let’s Go")
                        .primaryActionLabel()
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(.brand)
                .foregroundStyle(Color.onBrand)
            }
            Button { showLog = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.pencil")
                    Text("Log Workout")
                }
                .primaryActionLabel()
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(.white)
            .foregroundStyle(.white)
        }
    }

    // MARK: Description (expandable "MORE")

    @ViewBuilder private var description: some View {
        if let summary = workout.summary, !summary.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(summary)
                    .primaryLabelFont()
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(descExpanded ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)
                if summary.count > 120 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { descExpanded.toggle() }
                    } label: {
                        Text(descExpanded ? "LESS" : "MORE")
                            .scaledFont(15, weight: .bold, relativeTo: .subheadline)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Muscle groups (the granular data this app adds)

    @ViewBuilder private var muscleGroups: some View {
        if !workout.facets.muscleGroups.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("Muscle Groups")
                FlowLayout(spacing: 8) {
                    ForEach(workout.facets.muscleGroups, id: \.self) { slug in
                        tag(tax.muscle(slug))
                    }
                    ForEach(workout.facets.dumbbells ?? [], id: \.self) { slug in
                        tag(slug.replacingOccurrences(of: "-", with: " ").capitalized,
                            icon: "dumbbell")
                    }
                }
            }
        }
    }

    private func tag(_ text: String, icon: String? = nil) -> some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.caption2) }
            Text(text).scaledFont(14, weight: .medium, relativeTo: .subheadline)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .foregroundStyle(.white)
        .background(Color.white.opacity(0.10), in: Capsule())
    }

    // MARK: Moves

    private var moveCountLabel: String {
        let n = workout.displayMoves.count
        return n == 1 ? "1 move" : "\(n) moves"
    }

    @ViewBuilder private var movesSection: some View {
        if !workout.displayMoves.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("Moves", accessory: .text(moveCountLabel))
                ForEach(Array(workout.displayMoves.enumerated()), id: \.offset) { i, move in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(i + 1)")
                            .foregroundStyle(Color.brand)
                            .monospacedDigit()
                        Text(tax.move(move))
                            .foregroundStyle(.white)
                    }
                    .primaryLabelFont()
                }
            }
        }
    }

    // MARK: History

    @ViewBuilder private var historySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Your History", accessory: sessions.isEmpty ? nil : .count(sessions.count))
            if sessions.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "dumbbell")
                        .foregroundStyle(.white.opacity(0.4))
                    Text("Not logged yet. Tap + to record a session.")
                        .primaryLabelFont()
                        .foregroundStyle(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface(fillOpacity: 0.05)
            } else {
                VStack(spacing: 12) {
                    ForEach(sessions) { session in
                        NavigationLink { LogDetailView(log: session) } label: {
                            SessionSummaryRow(log: session, workout: workout)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// One logged session as a polished **session card** — the same dark, generative
/// language the rest of the detail screen speaks. The workout's gradient palette
/// + body-focus glyph anchor the row to the workout it belongs to, and the lime
/// Completed pip ties it to the LogDetailView's "earned reward" motif. Lifted
/// weights (or the note) become the headline line, so the row summarizes what
/// actually happened, not just *that* it happened.
struct SessionSummaryRow: View {
    let log: WorkoutLog
    let workout: Workout

    private var palette: [Color] { WorkoutArt.palette(for: workout) }
    private var glyph: String { WorkoutArt.glyph(for: workout) }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                LinearGradient(colors: palette,
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: glyph)
                    .resizable().scaledToFit()
                    .frame(width: 22, height: 22)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .frame(width: 44, height: 44)
            .clipShape(.rect(cornerRadius: AppRadius.thumbnail))

            VStack(alignment: .leading, spacing: 5) {
                Text(relativeLabel)
                    .scaledFont(15, weight: .semibold, relativeTo: .subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                Text(summaryLine)
                    .scaledFont(15, weight: .medium, relativeTo: .subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .cardSurface()
    }

    private var summaryLine: String {
        if !log.moveEntries.isEmpty {
            return log.moveEntries.compactMap { entry in
                guard let set = entry.topSet else { return nil }
                return "\(entry.label) \(formatted(set.weightValue)) \(set.weightUnit.label)"
            }
                .joined(separator: " · ")
        }
        if let note = log.note, !note.isEmpty { return note }
        return "Logged session"
    }

    private var relativeLabel: String {
        relativeSessionLabel(log.performedAt)
    }
}

func formatted(_ v: Double) -> String {
    v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
}

/// "Today" / "Yesterday" / "N days ago" / abbreviated date — the relative-date
/// label shared by session cards on both the History list and a workout-detail's
/// "Your History" section, so the two surfaces stay in sync.
func relativeSessionLabel(_ date: Date) -> String {
    let cal = Calendar.current
    if cal.isDateInToday(date) { return "Today" }
    if cal.isDateInYesterday(date) { return "Yesterday" }
    let days = cal.dateComponents([.day],
                                  from: cal.startOfDay(for: date),
                                  to: cal.startOfDay(for: .now)).day ?? 0
    if days > 1 && days < 7 { return "\(days) days ago" }
    return date.formatted(date: .abbreviated, time: .omitted)
}
