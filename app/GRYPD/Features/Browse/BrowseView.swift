import SwiftUI
import SwiftData

struct BrowseView: View {
    @Environment(CatalogStore.self) private var catalog
    @Query private var logs: [WorkoutLog]

    @State private var filter = WorkoutFilter()
    @State private var showFilters = false
    /// Month ids the user has manually collapsed. Every month starts expanded
    /// (filtered or not) so the full list is visible by default; tapping a month
    /// header collapses just that one.
    @State private var collapsedMonths: Set<Date> = []

    private var results: [Workout] { catalog.filtered(filter) }
    private var months: [WorkoutMonth] { results.byMonth() }
    private var lastDone: [String: Date] { LogHistory.lastDoneByWorkout(logs, catalog: catalog) }
    private var isSearching: Bool {
        !filter.search.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(months) { month in
                    let isCollapsed = isSearching ? false : collapsedMonths.contains(month.id)
                    MonthSection(
                        month: month,
                        isSearching: isSearching,
                        isCollapsed: isCollapsed,
                        taxonomy: catalog.taxonomy,
                        lastDone: lastDone,
                        toggle: {
                            guard !isSearching else { return }
                            withAnimation(.snappy) {
                                if isCollapsed { collapsedMonths.remove(month.id) }
                                else { collapsedMonths.insert(month.id) }
                            }
                        }
                    )
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Strength")
            .navigationDestination(for: Workout.self) { WorkoutDetailView(workout: $0) }
            .searchable(text: $filter.search, prompt: "Search by episode number")
            .keyboardType(.numberPad)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showFilters = true
                    } label: {
                        Image(systemName: filter.activeFacetCount > 0
                              ? "line.3.horizontal.decrease.circle.fill"
                              : "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .sheet(isPresented: $showFilters) {
                FilterSheet(filter: $filter, taxonomy: catalog.taxonomy,
                            resultCount: { catalog.filtered($0).count })
            }
            .overlay {
                if results.isEmpty {
                    ContentUnavailableView("No matches", systemImage: "magnifyingglass",
                                           description: Text("Try clearing some filters."))
                }
            }
        }
    }
}

// Hidden value-based link + card overlay: gives a clean bordered card with no
// disclosure chevron or row inset, matching the History session rows.
private struct WorkoutRowLink: View {
    let workout: Workout
    let taxonomy: Taxonomy
    let lastDone: Date?

    var body: some View {
        ZStack {
            NavigationLink(value: workout) { EmptyView() }
                .opacity(0)
            WorkoutRow(workout: workout,
                       taxonomy: taxonomy,
                       lastDone: lastDone)
        }
        .contentShape(.rect)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}

private struct MonthSection: View {
    let month: WorkoutMonth
    let isSearching: Bool
    let isCollapsed: Bool
    let taxonomy: Taxonomy
    let lastDone: [String: Date]
    let toggle: () -> Void

    var body: some View {
        Section {
            if !isCollapsed {
                ForEach(month.workouts) { workout in
                    WorkoutRowLink(
                        workout: workout,
                        taxonomy: taxonomy,
                        lastDone: lastDone[workout.id]
                    )
                }
            }
        } header: {
            MonthSectionHeader(
                label: month.label,
                count: month.workouts.count,
                isCollapsed: isCollapsed,
                toggle: toggle,
                noun: "workouts"
            )
            .padding(.vertical, 2)
        }
    }
}
