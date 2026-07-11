import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutLog.performedAt, order: .reverse) private var logs: [WorkoutLog]

    @Query private var goalRevisions: [WeeklyGoalRevision]

    @State private var pendingDelete: WorkoutLog?
    /// Month ids (month-start dates) whose sessions are collapsed. Empty = all expanded.
    @State private var collapsedMonths: Set<Date> = []
    @State private var search = ""

    var body: some View {
        NavigationStack {
            Group {
                if logs.isEmpty {
                    if weeklyGoalReport.currentWeek.isGraded {
                        VStack(spacing: AppSpacing.section) {
                            WeeklyGoalSummary(report: weeklyGoalReport)
                            emptyState
                        }
                        .padding(.horizontal, 16)
                    } else {
                        emptyState
                    }
                } else {
                    sessionList
                }
            }
            .navigationTitle("History")
            .searchable(text: $search, prompt: "Search by episode number")
            .keyboardType(.numberPad)
        }
    }

    /// Names the specific session in the delete confirmation so it isn't generic.
    private func deleteTitle(for log: WorkoutLog) -> String {
        guard let title = catalog.workout(id: log.workoutId)?.title else {
            return "Delete this session?"
        }
        return "Delete “\(title)”?"
    }

    @MainActor
    private var weeklyGoalReport: WeeklyGoalReport {
        WeeklyGoalEngine().report(logs: logs, revisions: goalRevisions, catalog: catalog)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No sessions yet", systemImage: "clock.arrow.circlepath")
        } description: {
            Text("Log a workout to start building your history.")
        } actions: {
            Button("Browse workouts") { router.selectedTab = .browse }
                .buttonStyle(.glassProminent)
                .tint(.brand)
                .foregroundStyle(Color.onBrand)
        }
    }

    // MARK: - Session list

    private var isSearching: Bool {
        !search.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Logs whose workout episode number matches the search query as a prefix
    /// (same rule as Browse: "2" hits episodes 2, 20, 21, …). Workouts without an
    /// episode, or logs whose workout left the catalog, never match a query.
    private var filteredLogs: [WorkoutLog] {
        guard isSearching else { return logs }
        let q = search.trimmingCharacters(in: .whitespaces)
        return logs.filter { log in
            guard let w = catalog.workout(id: log.workoutId),
                  let ep = w.episode else { return false }
            return String(ep).hasPrefix(q)
        }
    }

    private var sessionList: some View {
        List {
            Section {
                Group {
                    if weeklyGoalReport.currentWeek.isGraded {
                        WeeklyGoalSummary(report: weeklyGoalReport)
                    } else {
                        HistorySummaryHeader(logs: logs)
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            Section {
                if isSearching, filteredLogs.isEmpty {
                    ContentUnavailableView("No matches", systemImage: "magnifyingglass",
                                           description: Text("Try a different episode number."))
                        .listRowInsets(EdgeInsets(top: 24, leading: 16, bottom: 24, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }

            ForEach(HistoryStats.byMonth(filteredLogs), id: \.id) { month in
                let isCollapsed = isSearching ? false : collapsedMonths.contains(month.id)
                Section {
                    if !isCollapsed {
                        ForEach(month.logs) { log in
                            ZStack {
                                NavigationLink {
                                    LogDetailView(log: log)
                                } label: { EmptyView() }
                                    .opacity(0)
                                HistoryRow(log: log, workout: catalog.workout(id: log.workoutId),
                                           taxonomy: catalog.taxonomy)
                            }
                            .contentShape(.rect)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                // No `.destructive` role here: that makes the List
                                // animate the row out on tap, before the confirmation
                                // resolves. Deletion is deferred to the popover, so
                                // this is a plain red button that only arms the confirm.
                                Button {
                                    pendingDelete = log
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .tint(.red)
                            }
                            // Anchor the confirmation to this row so it appears
                            // beside the session being deleted, not centre-screen.
                            .confirmationPopover(
                                isPresented: Binding(
                                    get: { pendingDelete?.id == log.id },
                                    set: { if !$0 { pendingDelete = nil } }
                                ),
                                title: deleteTitle(for: log),
                                message: "This permanently removes the logged workout and its weights.",
                                confirmTitle: "Delete",
                                role: .destructive
                            ) {
                                context.delete(log)
                            }
                        }
                    }
                } header: {
                    MonthSectionHeader(label: month.label, count: month.logs.count,
                                        isCollapsed: isCollapsed) {
                        guard !isSearching else { return }
                        withAnimation(.snappy) {
                            if isCollapsed { collapsedMonths.remove(month.id) }
                            else { collapsedMonths.insert(month.id) }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.black.ignoresSafeArea())
    }

}

// MARK: - Summary header (glass)

private struct HistorySummaryHeader: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(\.dynamicTypeSize) private var typeSize
    let logs: [WorkoutLog]

    private var thisWeek: Int { HistoryStats.thisWeekCount(logs) }
    private var streak: Int { HistoryStats.streakWeeks(logs) }
    private var total: Int { logs.count }
    private var time: String { HistoryStats.timeLabel(minutes: HistoryStats.totalMinutes(logs, catalog: catalog)) }

    var body: some View {
        VStack(spacing: 18) {
            // Hero: this week
            VStack(spacing: 2) {
                Text("\(thisWeek)")
                    .scaledFont(52, weight: .bold, design: .rounded, relativeTo: .largeTitle)
                    .contentTransition(.numericText())
                    .foregroundStyle(.primary)
                Text("this week")
                    .primaryLabelFont()
                    .foregroundStyle(.secondary)
            }

            // Trio: streak · total · time — reflows to a column at accessibility sizes.
            let trio = Group {
                // A live streak lights the flame in brand lime; a broken (0) streak
                // stays dim so the green reads as an earned reward, not decoration.
                StatPiece(symbol: "flame.fill", value: "\(streak)", caption: streak == 1 ? "week streak" : "weeks streak",
                          symbolTint: streak > 0 ? .brand : .secondary)
                StatPiece(symbol: "checkmark.circle.fill", value: "\(total)", caption: total == 1 ? "session" : "sessions",
                          symbolTint: .brand)
                StatPiece(symbol: "clock.fill", value: time, caption: "total time")
            }
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) { trio }
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .top, spacing: 8) {
                    Spacer(minLength: 0); trio; Spacer(minLength: 0)
                }
            }
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .cardSurface(radius: AppRadius.glass)
    }
}

// MARK: - Weekly goal summary

private struct WeeklyGoalSummary: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let report: WeeklyGoalReport

    private var week: WeeklyGoalWeek { report.currentWeek }
    private var definition: WeeklyGoalDefinition? { week.definition }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if definition?.mode == .total {
                totalTile
            } else {
                categoryTiles
            }

            streakRow
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .featurePanel()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.brand)
                .frame(width: 34, height: 34)
                .background(Color.brand.opacity(0.14), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text("This week")
                    .sectionHeaderFont()
                    .foregroundStyle(.white)
                Text(dateRange)
                    .primaryLabelFont(weight: .medium)
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 0)
        }
    }

    private var dateRange: String {
        let start = week.interval.start
        let end = week.interval.end.addingTimeInterval(-1)
        return "\(start.formatted(.dateTime.month(.abbreviated).day())) – \(end.formatted(.dateTime.month(.abbreviated).day()))"
    }

    // MARK: - Total mode

    private var totalTile: some View {
        let target = definition?.totalTarget ?? 0
        let count = week.totalCount
        let remaining = max(0, target - count)
        return HStack(spacing: 18) {
            GoalRing(progress: fraction(count, target), size: 96, lineWidth: 8) {
                VStack(spacing: 0) {
                    Text("\(count)")
                        .scaledFont(30, weight: .bold, design: .rounded, relativeTo: .title)
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text("of \(target)")
                        .scaledFont(12, weight: .semibold, relativeTo: .caption2)
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Label {
                    Text("Weekly workouts")
                } icon: {
                    Image(systemName: "figure.strengthtraining.traditional")
                }
                .labelStyle(.titleAndIcon)
                .scaledFont(15, weight: .semibold, relativeTo: .subheadline)
                .foregroundStyle(.white)

                if week.isComplete {
                    Label("Goal complete", systemImage: "checkmark.circle.fill")
                        .scaledFont(14, weight: .semibold, relativeTo: .footnote)
                        .foregroundStyle(Color.brand)
                } else {
                    Text("\(remaining) more to go")
                        .scaledFont(14, weight: .medium, relativeTo: .footnote)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: AppRadius.card)
    }

    // MARK: - Granular mode

    @ViewBuilder private var categoryTiles: some View {
        let categories = WeeklyGoalCategory.allCases.filter { definition?.enabledTargets[$0.focus] != nil }
        let tiles = ForEach(categories) { category in
            GoalCategoryTile(category: category,
                             count: week.counts[category.focus, default: 0],
                             target: definition?.enabledTargets[category.focus] ?? 0,
                             stacked: typeSize.isAccessibilitySize)
        }
        // Three across normally; reflow to a single column at accessibility sizes so
        // the ring and its numbers never crush together.
        if typeSize.isAccessibilitySize {
            VStack(spacing: 10) { tiles }
        } else {
            HStack(alignment: .top, spacing: 10) { tiles }
        }
    }

    private func fraction(_ count: Int, _ target: Int) -> Double {
        target <= 0 ? 0 : min(1, Double(count) / Double(target))
    }

    // MARK: - Streaks

    private var streakRow: some View {
        HStack(spacing: 10) {
            StreakTile(symbol: "flame.fill", value: report.currentStreak,
                       label: "current streak", active: report.currentStreak > 0)
            StreakTile(symbol: "trophy.fill", value: report.bestStreak,
                       label: "best streak", active: report.bestStreak > 0)
        }
    }

    private var accessibilitySummary: String {
        if definition?.mode == .total {
            let target = definition?.totalTarget ?? 0
            return "This week, \(week.totalCount) of \(target) workouts, \(report.currentStreak) week current streak, \(report.bestStreak) week best streak"
        }
        let categories = WeeklyGoalCategory.allCases.compactMap { category -> String? in
            guard let target = definition?.enabledTargets[category.focus] else { return nil }
            return "\(category.label), \(week.counts[category.focus, default: 0]) of \(target)"
        }
        return "This week, \(categories.joined(separator: ", ")), \(report.currentStreak) week current streak, \(report.bestStreak) week best streak"
    }
}

private enum WeeklyGoalCategory: CaseIterable, Identifiable {
    case upperBody, lowerBody, totalBody

    var id: Self { self }

    var focus: WorkoutBodyFocus {
        switch self {
        case .upperBody: .upperBody
        case .lowerBody: .lowerBody
        case .totalBody: .totalBody
        }
    }

    var label: String {
        switch self {
        case .upperBody: "Upper body"
        case .lowerBody: "Lower body"
        case .totalBody: "Total body"
        }
    }

    /// One recognizable SF Symbol per body focus, chosen so the three tile glyphs
    /// read as distinct silhouettes at a glance.
    var symbol: String {
        switch self {
        case .upperBody: "figure.strengthtraining.traditional"
        case .lowerBody: "figure.strengthtraining.functional"
        case .totalBody: "figure.mixed.cardio"
        }
    }
}

// MARK: - Weekly goal tiles

/// A brand-lime progress ring with arbitrary centered content (a body-focus glyph
/// or the total count). The track is a faint white circle; the arc fills clockwise
/// from 12 o'clock.
private struct GoalRing<Center: View>: View {
    let progress: Double
    var size: CGFloat = 56
    var lineWidth: CGFloat = 6
    @ViewBuilder var center: () -> Center

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.brand, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            center()
        }
        .frame(width: size, height: size)
        .animation(.snappy, value: progress)
    }
}

/// One body-focus goal as a tile: a ring with the focus glyph, the `count / target`
/// beneath it, and the category name. When the target is met the glyph goes lime.
private struct GoalCategoryTile: View {
    let category: WeeklyGoalCategory
    let count: Int
    let target: Int
    /// At accessibility sizes the tiles stack full-width, so lay the ring and text
    /// out horizontally there instead of the narrow centered column.
    var stacked: Bool = false

    private var complete: Bool { count >= target }
    private var progress: Double { target <= 0 ? 0 : min(1, Double(count) / Double(target)) }

    private var ring: some View {
        GoalRing(progress: progress, size: 56) {
            Image(systemName: category.symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(complete ? Color.brand : .white.opacity(0.85))
        }
    }

    private var countLabel: some View {
        Text("\(count) / \(target)")
            .scaledFont(17, weight: .bold, design: .rounded, relativeTo: .headline)
            .foregroundStyle(.white)
            .contentTransition(.numericText())
    }

    private var name: some View {
        Text(category.label)
            .scaledFont(13, weight: .medium, relativeTo: .caption)
            .foregroundStyle(.white.opacity(0.55))
    }

    var body: some View {
        Group {
            if stacked {
                HStack(spacing: 14) {
                    ring
                    VStack(alignment: .leading, spacing: 2) {
                        name
                        countLabel
                    }
                    Spacer(minLength: 0)
                }
            } else {
                VStack(spacing: 10) {
                    ring
                    VStack(spacing: 2) {
                        countLabel
                        name.multilineTextAlignment(.center)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: stacked ? .leading : .center)
        .padding(.vertical, 16)
        .padding(.horizontal, stacked ? 16 : 8)
        .cardSurface(radius: AppRadius.card)
    }
}

/// A streak stat as a tile: a symbol that lights lime when the streak is alive,
/// with the number and caption beside it.
private struct StreakTile: View {
    let symbol: String
    let value: Int
    let label: String
    let active: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(active ? Color.brand : .white.opacity(0.4))
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(value)")
                    .scaledFont(22, weight: .bold, design: .rounded, relativeTo: .title3)
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                Text(label)
                    .scaledFont(13, weight: .medium, relativeTo: .footnote)
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .cardSurface(radius: AppRadius.card)
    }
}

/// One small stat in the header trio: symbol + value on top, caption beneath.
private struct StatPiece: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let symbol: String
    let value: String
    let caption: String
    /// Tint for the symbol only; the value stays `.primary` for legibility.
    /// Defaults to `.primary` so non-accented pieces render as before.
    var symbolTint: Color = .primary

    var body: some View {
        let content = VStack(spacing: 3) {
            Label {
                Text(value)
            } icon: {
                // Inner tint wins over the outer `.primary`, so only the glyph colors.
                Image(systemName: symbol).foregroundStyle(symbolTint)
            }
            .labelStyle(.titleAndIcon)
            .scaledFont(17, weight: .semibold, relativeTo: .headline)
            .foregroundStyle(.primary)
            Text(caption)
                .scaledFont(13, relativeTo: .caption)
                .foregroundStyle(.secondary)
        }
        if typeSize.isAccessibilitySize {
            content.frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
        } else {
            content.frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Session row

/// One logged session as a **session card** — the same dark, generative-artwork
/// language used by the "Your History" section on the workout-detail screen, so a
/// session reads as the same "kind" of record in both places. The workout's
/// gradient palette + body-focus glyph anchor the card to the workout it was; the
/// title headlines (since the list spans many workouts), with trainer · duration ·
/// relative date as the supporting meta. Bordered surface replaces row dividers.
struct HistoryRow: View {
    let log: WorkoutLog
    let workout: Workout?
    let taxonomy: Taxonomy

    private var title: String {
        workout?.title ?? "Unavailable workout"
    }

    private var palette: [Color] {
        workout.map { WorkoutArt.palette(for: $0) }
            ?? [Color(hex: 0x2E2E44), Color(hex: 0x141422)]
    }

    /// Same body-focus SF Symbol family used by the Browse artwork, so a session
    /// reads as the same "kind" of workout in both places.
    private var glyph: String {
        workout.map { WorkoutArt.glyph(for: $0) } ?? "questionmark.circle"
    }

    private var metaLine: String {
        guard let workout else {
            return log.performedAt.formatted(date: .abbreviated, time: .omitted)
        }
        var parts: [String] = []
        if let ep = workout.episode { parts.append("Ep \(ep)") }
        parts.append(taxonomy.trainer(workout.trainer))
        parts.append(workout.durationLabel)
        parts.append(relativeSessionLabel(log.performedAt))
        return parts.joined(separator: "  •  ")
    }

    /// The session's logged lifts, weightiest first, so two logs of the same
    /// workout read differently at a glance (e.g. "Squat 552 lb · Lunge 185 lb").
    /// Only weighted entries count — an empty session shows no lift line.
    private var liftsLine: String? {
        let lifts = log.moveEntries
            .compactMap { entry -> (MoveEntry, SetEntry)? in
                guard let set = entry.topSet, set.weightValue > 0 else { return nil }
                return (entry, set)
            }
            .sorted { $0.1.weightValue > $1.1.weightValue }
        guard !lifts.isEmpty else { return nil }
        return lifts
            .map { "\($0.0.label) \(formatted($0.1.weightValue)) \($0.1.weightUnit.label)" }
            .joined(separator: "  •  ")
    }

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
                Text(title)
                    .scaledFont(16, weight: .semibold, relativeTo: .subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(metaLine)
                    .scaledFont(14, weight: .medium, relativeTo: .footnote)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                if let liftsLine {
                    Label {
                        Text(liftsLine)
                            .scaledFont(13, weight: .semibold, relativeTo: .footnote)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } icon: {
                        Image(systemName: "dumbbell.fill")
                            .foregroundStyle(Color.brand)
                    }
                    .labelStyle(.titleAndIcon)
                    .imageScale(.small)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .cardSurface()
    }
}
