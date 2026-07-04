import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutLog.performedAt, order: .reverse) private var logs: [WorkoutLog]

    @State private var pendingDelete: WorkoutLog?
    /// Month ids (month-start dates) whose sessions are collapsed. Empty = all expanded.
    @State private var collapsedMonths: Set<Date> = []
    @State private var search = ""

    var body: some View {
        NavigationStack {
            Group {
                if logs.isEmpty {
                    emptyState
                } else {
                    sessionList
                }
            }
            .navigationTitle("History")
            .searchable(text: $search, prompt: "Search by episode number")
            .keyboardType(.numberPad)
            .alert(deleteAlertTitle,
                   isPresented: deleteDialogBinding,
                   presenting: pendingDelete) { log in
                Button("Delete", role: .destructive) {
                    context.delete(log)
                    pendingDelete = nil
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: { _ in
                Text("This permanently removes the logged workout and its weights.")
            }
        }
    }

    /// Names the specific session in the delete confirmation so it isn't generic.
    private var deleteAlertTitle: String {
        guard let log = pendingDelete,
              let title = catalog.workout(id: log.workoutId)?.title else {
            return "Delete this session?"
        }
        return "Delete “\(title)”?"
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
                HistorySummaryHeader(logs: logs)
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
                                // resolves. Deletion is deferred to the alert, so this
                                // is a plain red button that only arms the confirm.
                                Button {
                                    pendingDelete = log
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .tint(.red)
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

    private var deleteDialogBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } })
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
                    .font(.subheadline)
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
        .glassEffect(.regular, in: .rect(cornerRadius: AppRadius.glass))
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
            .font(.headline)
            .foregroundStyle(.primary)
            Text(caption)
                .font(.caption)
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
