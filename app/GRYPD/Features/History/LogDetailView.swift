import SwiftUI
import SwiftData

/// History › Session — the record of a *completed* workout.
///
/// It reuses the dark, generative-artwork hero from `WorkoutDetailView` (so a
/// logged session reads as the same "kind" of workout it was), but reframes it
/// as a finished accomplishment: a "Completed" badge with a relative date, then
/// the **weights you lifted** presented as big-number stat cards — the one thing
/// a logged session has that a browse detail doesn't. Everything is 100% native
/// and Dynamic-Type-driven, on the app's black background.
///
/// The catalog is replaced wholesale on update, so the joined `workout` can be
/// nil. That path is fully supported: each `MoveEntry` carries its own label, so
/// the lifted weights and note still render even when the workout is gone.
struct LogDetailView: View {
    let log: WorkoutLog
    @Environment(CatalogStore.self) private var catalog
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var isEditing = false
    @State private var pendingDelete = false

    private var workout: Workout? { catalog.workout(id: log.workoutId) }
    private var tax: Taxonomy { catalog.taxonomy }

    // Minimum weight-tile width. The grid fits as many columns as the available
    // width allows (≈3-up on a phone), so tiles fill the row edge-to-edge; the
    // scaled minimum drops it to 2/1 columns as the text size grows.
    @ScaledMetric(relativeTo: .largeTitle) private var tileMinWidth: CGFloat = 100

    var body: some View {
        HeroDetailLayout {
            DetailHero(workout: workout) {
                VStack(alignment: .leading, spacing: 10) {
                    completedBadge

                    Text(heroTitle)
                        .heroTitleFont()
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)

                    if let heroMeta {
                        Text(heroMeta)
                            .primaryLabelFont(weight: .medium)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
            }
        } controls: {
            Menu {
                Button { isEditing = true } label: {
                    Label("Edit Session", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    pendingDelete = true
                } label: {
                    Label("Delete Session", systemImage: "trash")
                }
                if let url = workout?.appleURL {
                    Button { openURL(url) } label: {
                        Label("Open in Apple Fitness+", systemImage: "arrow.up.forward.app")
                    }
                    ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            // Anchor the confirmation to the ⋯ menu the delete was chosen from,
            // so the bubble points at it instead of appearing centre-screen.
            .confirmationPopover(
                isPresented: $pendingDelete,
                title: deleteAlertTitle,
                message: "This permanently removes the logged workout and its weights.",
                confirmTitle: "Delete",
                role: .destructive
            ) {
                context.delete(log)
                dismiss()
            }
        } content: {
            if workout == nil { unavailableBanner }
            metricsSection
            liftedSection
            noteSection
            detailsSection
            if workout != nil { actions }
        }
        .sheet(isPresented: $isEditing) {
            LogSessionView(editing: log, workout: workout)
        }
    }

    /// Names the specific session in the delete confirmation, matching History's
    /// swipe-to-delete alert. Falls back when the workout left the catalog.
    private var deleteAlertTitle: String {
        guard let title = workout?.title else { return "Delete this session?" }
        return "Delete “\(title)”?"
    }

    private var heroTitle: String {
        workout?.title ?? "Unavailable workout"
    }

    // MARK: - Hero badge

    /// The "earned reward" moment: a lime capsule that reads as a checked-off
    /// session, paired with how long ago it happened.
    private var completedBadge: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .scaledFont(12, weight: .heavy, relativeTo: .caption)
                Text("COMPLETED")
                    .scaledFont(13, weight: .bold, relativeTo: .caption)
                    .kerning(0.6)
            }
            .foregroundStyle(Color.onBrand)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color.brand, in: Capsule())

            Text(relativeLabel)
                .scaledFont(14, weight: .semibold, relativeTo: .subheadline)
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    private var heroMeta: String? {
        guard let workout else { return nil }
        return dotJoined([tax.trainer(workout.trainer), workout.durationLabel])
    }

    // MARK: - State banners

    private var unavailableBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.brand)
            Text("This workout is no longer in the catalog. Your log is preserved.")
                .scaledFont(15, relativeTo: .subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: 16, fillOpacity: 0.05)
    }

    // MARK: - Active calories (manual)

    /// The session's hand-entered active calories as a single big-number stat tile.
    /// Uses the same `flame.fill` glyph as the Log session sheet's Active Calories
    /// card. Renders nothing when no calories were logged.
    @ViewBuilder private var metricsSection: some View {
        if let kcal = log.activeEnergyKcal {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader("Metrics")
                CalorieTile(kcal: Int(kcal.rounded()))
            }
        }
    }

    // MARK: - Lifted (centerpiece)

    private var liftedSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Lifted", accessory: log.moveEntries.isEmpty ? nil : .text(moveCountLabel))
            if log.moveEntries.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "dumbbell")
                        .foregroundStyle(.white.opacity(0.4))
                    Text("No weights logged for this session.")
                        .primaryLabelFont()
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.vertical, 4)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: tileMinWidth), spacing: 12)],
                          alignment: .leading, spacing: 12) {
                    ForEach(log.orderedMoveEntries) { entry in
                        if let topSet = entry.topSet {
                            WeightCard(label: entry.label,
                                       set: topSet,
                                       subtitle: setContextLabel(for: entry))
                        }
                    }
                }
            }
        }
    }

    private var moveCountLabel: String {
        let n = log.moveEntries.count
        return n == 1 ? "1 move" : "\(n) moves"
    }

    // MARK: - Note (journal)

    @ViewBuilder private var noteSection: some View {
        if let note = log.note, !note.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader("Note")
                HStack(alignment: .top, spacing: 14) {
                    Capsule()
                        .fill(Color.brand)
                        .frame(width: 3)
                    Text(note)
                        .primaryLabelFont()
                        .foregroundStyle(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
                .cardSurface(fillOpacity: 0.05)
            }
        }
    }

    // MARK: - Details (receipt fine print)

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Details")
            VStack(spacing: 0) {
                detailRow("Date", fullDateLabel)
                if let workout {
                    divider
                    detailRow("Focus", tax.bodyFocus(workout.facets.bodyFocus))
                    if !workout.facets.equipment.isEmpty {
                        divider
                        detailRow("Equipment",
                                  workout.facets.equipment.map { tax.equipmentLabel($0) }
                                    .joined(separator: ", "))
                    }
                }
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .primaryLabelFont()
                .foregroundStyle(.white.opacity(0.5))
            Spacer(minLength: 16)
            Text(value)
                .primaryLabelFont(weight: .medium)
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 12)
    }

    // MARK: - Actions

    @ViewBuilder private var actions: some View {
        if let workout {
            NavigationLink { WorkoutDetailView(workout: workout) } label: {
                HStack(spacing: 8) {
                    Text("View Workout")
                    Image(systemName: "chevron.right")
                        .scaledFont(13, weight: .semibold, relativeTo: .subheadline)
                }
                .primaryActionLabel()
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(.white)
            .foregroundStyle(.white)
        }
    }

    // MARK: - Date helpers

    /// Warm, human date for the hero badge: Today / Yesterday / N days ago, then
    /// an abbreviated date once it's more than a week old.
    private var relativeLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(log.performedAt) { return "Today" }
        if cal.isDateInYesterday(log.performedAt) { return "Yesterday" }
        let days = cal.dateComponents([.day],
                                      from: cal.startOfDay(for: log.performedAt),
                                      to: cal.startOfDay(for: .now)).day ?? 0
        if days > 1 && days < 7 { return "\(days) days ago" }
        return log.performedAt.formatted(date: .abbreviated, time: .omitted)
    }

    /// Full receipt date: "Tuesday, June 24, 2026".
    private var fullDateLabel: String {
        log.performedAt.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }

    private func dotJoined(_ parts: [String]) -> String {
        parts.joined(separator: "  •  ")
    }

    private func setContextLabel(for entry: MoveEntry) -> String {
        let sets = entry.orderedSets
        let setDetails = sets.map(setDetailLabel).filter { !$0.isEmpty }
        if sets.count <= 3 && !setDetails.isEmpty {
            return setDetails.joined(separator: " · ")
        }

        var parts = [setCountLabel(sets.count)]
        let reps = sets.compactMap(\.reps).filter { $0 > 0 }
        if let min = reps.min(), let max = reps.max() {
            parts.append(min == max ? "\(min) reps" : "\(min)-\(max) reps")
        }
        let seconds = sets.compactMap(\.seconds).filter { $0 > 0 }
        if !seconds.isEmpty {
            let average = seconds.reduce(0, +) / seconds.count
            parts.append("~\(timerLabel(average))")
        }
        return parts.joined(separator: " · ")
    }

    private func setDetailLabel(_ set: SetEntry) -> String {
        var parts: [String] = []
        if let reps = set.reps, reps > 0 {
            parts.append("\(reps) reps")
        }
        if let seconds = set.seconds, seconds > 0 {
            parts.append(timerLabel(seconds))
        }
        return parts.joined(separator: " · ")
    }

    private func timerLabel(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds)s" : "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    private func setCountLabel(_ count: Int) -> String {
        count == 1 ? "1 set" : "\(count) sets"
    }
}

// MARK: - Calorie tile

/// The hand-entered active calories for a session as a big-number stat tile —
/// the same visual language as `WeightCard`, with the `flame.fill` glyph that the
/// Log session sheet's Active Calories card uses.
private struct CalorieTile: View {
    let kcal: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Image(systemName: "flame.fill")
                .scaledFont(20, weight: .bold, relativeTo: .title3)
                .foregroundStyle(Color.brand)
            Text("\(kcal)")
                .scaledFont(32, weight: .bold, design: .rounded, relativeTo: .largeTitle)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("cal")
                .scaledFont(14, weight: .bold, relativeTo: .subheadline)
                .foregroundStyle(Color.brand)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .cardSurface()
    }
}

// MARK: - Weight card

/// One lifted move as a big-number stat tile: the weight is the hero, the unit
/// accents it in brand lime, and the move name grounds it. Stretches to fill its
/// grid column so the tiles read as an even stat board that spans the full width.
private struct WeightCard: View {
    let label: String
    let set: SetEntry
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(formatted(set.weightValue))
                    .scaledFont(32, weight: .bold, design: .rounded, relativeTo: .largeTitle)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(set.weightUnit.label)
                    .scaledFont(14, weight: .bold, relativeTo: .subheadline)
                    .foregroundStyle(Color.brand)
            }
            Text(label)
                .scaledFont(13, weight: .medium, relativeTo: .footnote)
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .scaledFont(12, weight: .semibold, relativeTo: .caption)
                .foregroundStyle(.white.opacity(0.42))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .cardSurface()
    }
}
