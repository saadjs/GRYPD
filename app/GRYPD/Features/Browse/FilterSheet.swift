import SwiftUI

/// Full-screen filter sheet modeled on the Apple Fitness+ "Filter: Strength"
/// panel: a dark canvas with a custom header (cancel / live result count / apply),
/// clock-face duration dials, and two-column capsule grids for each facet.
///
/// Edits are made to a local `draft` and only committed on ✓ (apply); ✕ discards —
/// matching Fitness+ semantics, which the live-binding Form version couldn't offer.
struct FilterSheet: View {
    @Binding var filter: WorkoutFilter
    let taxonomy: Taxonomy
    /// Live result count for the current draft (Fitness+ shows "N Results").
    let resultCount: (WorkoutFilter) -> Int
    @Environment(\.dismiss) private var dismiss

    @State private var draft: WorkoutFilter
    // Capsule heights track the text size so labels never clip under Dynamic Type.
    @ScaledMetric(relativeTo: .subheadline) private var gridButtonHeight: CGFloat = 32

    init(filter: Binding<WorkoutFilter>,
         taxonomy: Taxonomy,
         resultCount: @escaping (WorkoutFilter) -> Int) {
        self._filter = filter
        self.taxonomy = taxonomy
        self.resultCount = resultCount
        self._draft = State(initialValue: filter.wrappedValue)
    }

    private let durations = [10, 20, 30]
    private let focuses = ["upper-body", "lower-body", "total-body"]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 34) {
                        Text("\(resultCount(draft)) Results")
                            .scaledFont(14, relativeTo: .subheadline)
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 4)

                        timeSection
                        gridSection("Body Focus",
                                    focuses.map { (taxonomy.bodyFocus($0), $0) },
                                    isOn: { draft.bodyFocus.contains($0) },
                                    toggle: { draft.toggle($0, in: \.bodyFocus) })
                        gridSection("Muscle Groups",
                                    taxonomy.muscleGroupsSorted.map { ($0.label, $0.slug) },
                                    isOn: { draft.muscleGroups.contains($0) },
                                    toggle: { draft.toggle($0, in: \.muscleGroups) })
                        gridSection("Equipment",
                                    taxonomy.equipmentSorted.map { ($0.label, $0.slug) },
                                    isOn: { draft.equipment.contains($0) },
                                    toggle: { draft.toggle($0, in: \.equipment) })
                        gridSection("Trainer",
                                    taxonomy.trainersSorted.map { ($0.label, $0.slug) },
                                    isOn: { draft.trainers.contains($0) },
                                    toggle: { draft.toggle($0, in: \.trainers) })
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 48)
                }
            }
            .navigationTitle("Filter: Strength")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        filter = draft
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.brand)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheetPresentation()
        .presentationBackground(.black)
    }

    // MARK: Time (clock-face dials)

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Time", showsClearAll: true)
            HStack(spacing: 14) {
                ForEach(durations, id: \.self) { mins in
                    DurationDial(minutes: mins,
                                 selected: draft.durations.contains(mins)) {
                        draft.toggle(mins, in: \.durations)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Facet grids

    private func gridSection<T: Hashable>(_ title: String,
                                          _ options: [(String, T)],
                                          isOn: @escaping (T) -> Bool,
                                          toggle: @escaping (T) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12),
                                     count: 3),
                      spacing: 12) {
                ForEach(options, id: \.1) { label, value in
                    let selected = isOn(value)
                    Button { toggle(value) } label: {
                        Text(label)
                            .font(.subheadline.weight(.semibold))   // matches Browse row titles
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .frame(height: gridButtonHeight)
                            .foregroundStyle(selected ? Color.onBrand : .white)
                            .background(selected ? Color.brand : Color.white.opacity(0.08),
                                        in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func sectionHeader(_ text: String, showsClearAll: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text)
                .sectionHeaderFont()
                .foregroundStyle(.white)
            Spacer(minLength: 16)
            if showsClearAll && draft.activeFacetCount > 0 {
                Button {
                    draft.clearFacets()
                } label: {
                    Text("Clear All")
                        .scaledFont(18, weight: .medium, relativeTo: .title3)
                        .foregroundStyle(Color.brand)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// A clock-face style duration selector, matching the Fitness+ "Time" dials.
private struct DurationDial: View {
    let minutes: Int
    let selected: Bool
    let action: () -> Void

    private let size: CGFloat = 62

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Color.white.opacity(selected ? 0.10 : 0.03))
                ticks
                VStack(spacing: 0) {
                    Text("\(minutes)")
                        .scaledFont(19, weight: .semibold, design: .rounded, relativeTo: .title3)
                    Text("MIN")
                        .scaledFont(8, weight: .semibold, relativeTo: .caption2)
                        .tracking(0.8)
                }
                .foregroundStyle(selected ? Color.brand : .white.opacity(0.4))
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
    }

    /// 60 radial ticks with longer marks every 5 — a clock dial.
    private var ticks: some View {
        ForEach(0..<60, id: \.self) { i in
            Capsule()
                .fill(selected ? Color.white.opacity(0.85) : Color.white.opacity(0.16))
                .frame(width: 1.2, height: i % 5 == 0 ? 6 : 3.5)
                .offset(y: -(size / 2 - 4))
                .rotationEffect(.degrees(Double(i) / 60 * 360))
        }
    }
}

/// Minimal wrapping layout (native Layout API, iOS 16+).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [CGFloat] = [0]
        var x: CGFloat = 0, height: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let s = view.sizeThatFits(.unspecified)
            if x + s.width > maxWidth, x > 0 {
                height += rowHeight + spacing
                rows.append(0); x = 0; rowHeight = 0
            }
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
        height += rowHeight
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let s = view.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX {
                y += rowHeight + spacing; x = bounds.minX; rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}
