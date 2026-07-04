import SwiftUI
import SwiftData
import Charts

/// Progress is exercise-first: the top question is whether a specific movement
/// is getting stronger over time.
struct ProgressionView: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var typeSize
    @Query(sort: \WorkoutLog.performedAt, order: .reverse) private var logs: [WorkoutLog]
    @AppStorage("defaultUnit") private var defaultUnitRaw = WeightUnit.lb.rawValue

    @State private var range: ProgressRange = .sixMonths
    @State private var selectedMoveSlug: String?

    private var displayUnit: WeightUnit { WeightUnit(rawValue: defaultUnitRaw) ?? .lb }
    private var filteredLogs: [WorkoutLog] { ProgressionStats.logs(logs, in: range) }
    private var summaries: [ExerciseProgressSummary] {
        ProgressionStats.exerciseSummaries(logs: filteredLogs, catalog: catalog, displayUnit: displayUnit)
    }
    /// Unfiltered history, so the PR tile can tell a true all-time best from a merely
    /// range-scoped one (see `ProgressionStats.prCount`).
    private var allTimePoints: [ExerciseProgressPoint] {
        ProgressionStats.exercisePoints(logs: logs, catalog: catalog, displayUnit: displayUnit)
    }
    private var visibleSummaries: [ExerciseProgressSummary] {
        summaries.filter { summary in
            selectedMoveSlug == nil || selectedMoveSlug == summary.moveSlug
        }
    }
    var body: some View {
        NavigationStack {
            Group {
                if logs.isEmpty {
                    emptyState
                } else {
                    dashboard
                }
            }
            .navigationTitle("Progress")
            .background(Color.black.ignoresSafeArea())
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Nothing to chart yet", systemImage: "chart.line.uptrend.xyaxis")
        } description: {
            Text("Log your sets to see each move's progress over time.")
        } actions: {
            Button("Browse workouts") { router.selectedTab = .browse }
                .buttonStyle(.glassProminent)
                .tint(.brand)
                .foregroundStyle(Color.onBrand)
        }
        .background(Color.black.ignoresSafeArea())
    }

    private var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                overview
                rangePicker
                exerciseSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 36)
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(range.subtitle)
                .scaledFont(16, weight: .medium, relativeTo: .subheadline)
                .foregroundStyle(.white.opacity(0.58))

            metricTiles
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .featurePanel()
    }

    @ViewBuilder
    private var metricTiles: some View {
        let prCount = ProgressionStats.prCount(summaries, allTimePoints: allTimePoints)
        let tiles = [
            ProgressMetricTile(symbol: "trophy.fill",
                               value: "\(prCount)",
                               label: prCount == 1 ? "new PR" : "new PRs",
                               tint: .brand),
            ProgressMetricTile(symbol: "figure.strengthtraining.traditional",
                               value: "\(summaries.count)",
                               label: "tracked moves",
                               tint: Color(hex: 0x64D2FF)),
            ProgressMetricTile(symbol: "checkmark.circle.fill",
                               value: "\(filteredLogs.count)",
                               label: filteredLogs.count == 1 ? "session" : "sessions",
                               tint: .brand)
        ]

        if typeSize.isAccessibilitySize {
            // At large text sizes stack vertically so labels never clip.
            VStack(spacing: 12) { ForEach(0..<tiles.count, id: \.self) { tiles[$0] } }
        } else {
            // Equal-width columns; maxHeight lets every tile match the tallest.
            HStack(spacing: 12) {
                ForEach(0..<tiles.count, id: \.self) { tiles[$0] }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var rangePicker: some View {
        Picker("Time Range", selection: $range) {
            ForEach(ProgressRange.allCases) { range in
                Text(range.label).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .tint(.brand)
    }

    @ViewBuilder private var exerciseSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Exercise Progression", accessory: .count(visibleSummaries.count))
            if summaries.isEmpty {
                ProgressUnavailableCard(title: "No exercise entries",
                                        message: "This range has sessions, but no logged moves yet.")
            } else {
                ExerciseFilterBar(summaries: summaries,
                                  selectedMoveSlug: $selectedMoveSlug)

                if visibleSummaries.isEmpty {
                    ProgressUnavailableCard(title: "No matching exercise",
                                            message: "Clear the exercise filter to show every move.")
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)],
                          alignment: .leading, spacing: 14) {
                    ForEach(visibleSummaries) { summary in
                        NavigationLink {
                            ExerciseProgressDetail(moveSlug: summary.moveSlug,
                                                   title: summary.title,
                                                   range: range)
                        } label: {
                            ExerciseProgressCard(summary: summary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Detail: exercise

struct ExerciseProgressDetail: View {
    let moveSlug: String
    let title: String
    let range: ProgressRange

    @Environment(CatalogStore.self) private var catalog
    @Query(sort: \WorkoutLog.performedAt, order: .reverse) private var logs: [WorkoutLog]
    @AppStorage("defaultUnit") private var defaultUnitRaw = WeightUnit.lb.rawValue
    @State private var selectedPoint: ExerciseProgressPoint?
    @State private var mode: MetricMode = .intensity

    private var displayUnit: WeightUnit { WeightUnit(rawValue: defaultUnitRaw) ?? .lb }
    private var points: [ExerciseProgressPoint] {
        ProgressionStats.exercisePoints(logs: ProgressionStats.logs(logs, in: range),
                                        moveSlug: moveSlug,
                                        catalog: catalog,
                                        displayUnit: displayUnit)
    }

    private var summary: ExerciseProgressSummary? {
        ProgressionStats.exerciseSummary(moveSlug: moveSlug, title: title, points: points)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let summary {
                    ExerciseDetailHero(summary: summary, range: range, mode: mode)
                    // Toggle sits between hero and chart so it governs both; hero's
                    // big number and the chart series always show the same metric.
                    metricPicker(kind: summary.kind)
                    ExerciseLineChart(points: points, mode: mode, selectedPoint: $selectedPoint)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 36)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sensoryFeedback(.selection, trigger: selectedPoint?.id)
        .onChange(of: mode) { selectedPoint = nil }
    }

    private func metricPicker(kind: MetricKind) -> some View {
        Picker("Metric", selection: $mode) {
            ForEach(MetricMode.allCases) { mode in
                Text(kind.segmentTitle(mode)).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .tint(.brand)
    }
}

// MARK: - Cards

private struct ExerciseProgressCard: View {
    let summary: ExerciseProgressSummary

    private var improving: Bool { summary.isImproving(.intensity) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(summary.title)
                        .scaledFont(18, weight: .bold, relativeTo: .headline)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(summary.contextLabel)
                        .scaledFont(14, weight: .medium, relativeTo: .subheadline)
                        .foregroundStyle(.white.opacity(0.48))
                }
                Spacer(minLength: 0)
                Image(systemName: improving ? "arrow.up.right" : "arrow.down.right")
                    .scaledFont(15, weight: .bold, relativeTo: .subheadline)
                    .foregroundStyle(improving ? Color.brand : Color(hex: 0xFF453A))
            }

            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(summary.headlineValue(.intensity))
                    .scaledFont(42, weight: .bold, design: .rounded, relativeTo: .largeTitle)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                if let unit = summary.headlineUnit(.intensity) {
                    Text(unit)
                        .scaledFont(15, weight: .bold, relativeTo: .subheadline)
                        .foregroundStyle(Color.brand)
                }
                Text(summary.deltaLabel(.intensity))
                    .scaledFont(15, weight: .bold, relativeTo: .subheadline)
                    .foregroundStyle(improving ? Color.brand : Color(hex: 0xFF453A))
                    .padding(.leading, 4)
            }
            // Name the metric so a computed est. max never reads as a weight lifted.
            Text(summary.kind.intensityLabel)
                .scaledFont(13, weight: .semibold, relativeTo: .caption)
                .foregroundStyle(.white.opacity(0.5))

            Sparkline(points: summary.points.map(\.intensity), tint: improving ? .brand : Color(hex: 0xFF453A))
                .frame(height: 54)
                .accessibilityHidden(true)

            HStack {
                ProgressCaption(title: "Start", value: summary.startLabel(.intensity))
                ProgressCaption(title: "Best", value: summary.bestLabel(.intensity))
                ProgressCaption(title: "Latest", value: summary.latestDateLabel)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 236, alignment: .topLeading)
        .cardSurface(radius: AppRadius.panel, strokeOpacity: 0.08)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(summary.title), \(summary.kind.intensityLabel) \(summary.headlineValue(.intensity)) \(summary.headlineUnit(.intensity) ?? ""), \(summary.deltaLabel(.intensity))")
    }
}

private struct ExerciseFilterBar: View {
    let summaries: [ExerciseProgressSummary]
    @Binding var selectedMoveSlug: String?

    @Environment(\.dynamicTypeSize) private var typeSize

    private var selectedTitle: String {
        guard let selectedMoveSlug,
              let summary = summaries.first(where: { $0.moveSlug == selectedMoveSlug }) else {
            return "All Exercises"
        }
        return summary.title
    }

    var body: some View {
        controls
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controls: some View {
        Menu {
            Button {
                selectedMoveSlug = nil
            } label: {
                if selectedMoveSlug == nil {
                    Label("All Exercises", systemImage: "checkmark")
                } else {
                    Text("All Exercises")
                }
            }

            Divider()

            ForEach(summaries.sorted { $0.title < $1.title }) { summary in
                Button {
                    selectedMoveSlug = summary.moveSlug
                } label: {
                    if selectedMoveSlug == summary.moveSlug {
                        Label(summary.title, systemImage: "checkmark")
                    } else {
                        Text(summary.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(selectedTitle)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .scaledFont(12, weight: .bold, relativeTo: .caption)
                    .foregroundStyle(Color.brand)
            }
            .scaledFont(15, weight: .semibold, relativeTo: .subheadline)
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .frame(height: 36)
            .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: false)
            .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil, alignment: .leading)
            .background(Color.white.opacity(0.07), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ProgressMetricTile: View {
    let symbol: String
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .scaledFont(17, weight: .bold, relativeTo: .body)
                .foregroundStyle(tint)
            Text(value)
                .scaledFont(30, weight: .bold, design: .rounded, relativeTo: .title)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
            Text(label)
                .scaledFont(13, weight: .medium, relativeTo: .caption)
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 132, maxHeight: .infinity, alignment: .leading)
        .cardSurface()
    }
}

private struct ExerciseDetailHero: View {
    let summary: ExerciseProgressSummary
    let range: ProgressRange
    let mode: MetricMode

    private var improving: Bool { summary.isImproving(mode) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(range.subtitle)
                Spacer(minLength: 8)
                Text(summary.kind.segmentTitle(mode))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .scaledFont(15, weight: .semibold, relativeTo: .subheadline)
            .foregroundStyle(Color.brand)

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(summary.headlineValue(mode))
                    .scaledFont(56, weight: .bold, design: .rounded, relativeTo: .largeTitle)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .contentTransition(.numericText())
                if let unit = summary.headlineUnit(mode) {
                    Text(unit)
                        .scaledFont(17, weight: .bold, relativeTo: .headline)
                        .foregroundStyle(Color.brand)
                }
                Text(summary.deltaLabel(mode))
                    .scaledFont(17, weight: .bold, relativeTo: .headline)
                    .foregroundStyle(improving ? Color.brand : Color(hex: 0xFF453A))
            }
            .animation(.easeOut(duration: 0.18), value: mode)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)],
                      alignment: .leading, spacing: 12) {
                ProgressCaption(title: "Start", value: summary.startLabel(mode))
                ProgressCaption(title: "Best", value: summary.bestLabel(mode))
                ProgressCaption(title: "Entries", value: "\(summary.points.count)")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .featurePanel()
    }
}

private struct ExerciseLineChart: View {
    let points: [ExerciseProgressPoint]
    let mode: MetricMode
    @Binding var selectedPoint: ExerciseProgressPoint?

    private func plotted(_ point: ExerciseProgressPoint) -> Double { point.value(for: mode) }
    private var kind: MetricKind { series.first?.kind ?? points.first?.kind ?? .weighted }

    /// One point per day, so a line/bar has a single y per x. See
    /// `ProgressionStats.dailySeries` for how intensity (best set) and volume
    /// (summed across the day's sessions) collapse differently.
    private var series: [ExerciseProgressPoint] {
        ProgressionStats.dailySeries(points, mode: mode)
    }

    private var valueDomain: ClosedRange<Double> {
        guard let minValue = series.map(plotted).min(),
              let maxValue = series.map(plotted).max() else {
            return 0...1
        }
        let spread = max(maxValue - minValue, 1)
        let padding = max(spread * 0.25, 2.5)
        // Bars read from a zero baseline; a line can float on a padded window.
        let lower = mode == .volume ? 0 : max(0, minValue - padding)
        return lower...(maxValue + padding)
    }

    /// Peak on the shown metric — anchored as a PR marker in the line (intensity)
    /// view only; the bar (volume) view reads its own tallest bar without a label.
    private var bestPoint: ExerciseProgressPoint? {
        series.max { plotted($0) < plotted($1) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("History")
            chartReadout
                .frame(minHeight: 76, alignment: .top)
                .animation(.easeOut(duration: 0.12), value: selectedPoint?.id)
            chart
                .frame(height: 240)
        }
        .padding(16)
        .cardSurface(radius: AppRadius.panel, strokeOpacity: 0.08)
    }

    @ViewBuilder private var chartReadout: some View {
        if let selectedPoint {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(selectedPoint.kind.valueText(plotted(selectedPoint)))
                            .scaledFont(30, weight: .bold, design: .rounded, relativeTo: .title)
                            .foregroundStyle(.white)
                            .monospacedDigit()
                        if let unit = selectedPoint.kind.unitText(weightUnit: selectedPoint.unit) {
                            Text(unit)
                                .scaledFont(14, weight: .bold, relativeTo: .subheadline)
                                .foregroundStyle(Color.brand)
                        }
                    }
                    Text(selectedPoint.workoutTitle)
                        .scaledFont(14, weight: .semibold, relativeTo: .subheadline)
                        .foregroundStyle(.white.opacity(0.64))
                        .lineLimit(1)
                    if let meta = selectedPoint.workoutMeta {
                        Text(meta)
                            .scaledFont(13, weight: .semibold, relativeTo: .caption)
                            .foregroundStyle(.white.opacity(0.48))
                            .lineLimit(1)
                    }
                    if mode == .intensity, let effort = selectedPoint.effortLabel {
                        Text(effort)
                            .scaledFont(13, weight: .semibold, relativeTo: .caption)
                            .foregroundStyle(.white.opacity(0.48))
                    }
                }
                Spacer(minLength: 12)
                Text(selectedPoint.date.formatted(date: .abbreviated, time: .omitted))
                    .scaledFont(14, weight: .semibold, relativeTo: .subheadline)
                    .foregroundStyle(.white.opacity(0.48))
                    .multilineTextAlignment(.trailing)
            }
        } else {
            // Reserve the readout's space so the chart doesn't shift while scrubbing.
            Color.clear
        }
    }

    private var chart: some View {
        Chart {
            ForEach(series) { point in
                if mode == .volume {
                    BarMark(x: .value("Date", point.date, unit: .day),
                            y: .value("Volume", plotted(point)))
                        .foregroundStyle(Color.brand.opacity(selectedPoint == nil ? 0.85 : 0.4))
                        .cornerRadius(4)
                } else {
                    LineMark(x: .value("Date", point.date),
                             y: .value("Value", plotted(point)))
                        .foregroundStyle(Color.brand)
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Date", point.date),
                              y: .value("Value", plotted(point)))
                        .foregroundStyle(Color.brand.opacity(0.42))
                        .symbolSize(32)
                }
            }

            // Anchor the "Best" stat to the line, but hide it while scrubbing and in
            // the volume (bar) view, where the tallest bar already reads as the peak.
            if mode == .intensity, let bestPoint, selectedPoint == nil {
                PointMark(x: .value("Date", bestPoint.date),
                          y: .value("Value", plotted(bestPoint)))
                    .foregroundStyle(Color.brand)
                    .symbolSize(70)
                    .symbol {
                        Circle()
                            .fill(.black)
                            .overlay(Circle().stroke(Color.brand, lineWidth: 2))
                            .frame(width: 11, height: 11)
                    }
                    .annotation(position: .top, spacing: 5) {
                        Text("PR")
                            .scaledFont(10, weight: .heavy, relativeTo: .caption2)
                            .tracking(0.6)
                            .foregroundStyle(Color.brand)
                    }
            }

            if let selectedPoint {
                RuleMark(x: .value("Selected date", selectedPoint.date))
                    .foregroundStyle(Color.white.opacity(0.36))
                    .lineStyle(.init(lineWidth: 1))

                if mode == .intensity {
                    PointMark(x: .value("Selected date", selectedPoint.date),
                              y: .value("Value", plotted(selectedPoint)))
                        .foregroundStyle(Color.black)
                        .symbolSize(78)

                    PointMark(x: .value("Selected date", selectedPoint.date),
                              y: .value("Value", plotted(selectedPoint)))
                        .foregroundStyle(Color.brand)
                        .symbolSize(38)
                }
            }
        }
        .chartYScale(domain: valueDomain)
        .chartXAxis {
            // Labels only — no vertical gridlines competing with the data line.
            AxisMarks(values: .automatic(desiredCount: 4, roundLowerBound: true, roundUpperBound: true)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day(),
                               collisionResolution: .greedy)
                    .font(.caption2)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                // Format ticks on the metric's own scale (e.g. timed as m:ss) rather
                // than raw doubles.
                if let raw = value.as(Double.self) {
                    AxisValueLabel { Text(kind.valueText(raw)) }
                } else {
                    AxisValueLabel()
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let plotFrameAnchor = proxy.plotFrame {
                    let plotFrame = geometry[plotFrameAnchor]
                    Rectangle()
                        .fill(.clear)
                        .contentShape(.rect)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let x = value.location.x - plotFrame.origin.x
                                    guard x >= 0, x <= plotFrame.width,
                                          let date: Date = proxy.value(atX: x) else {
                                        return
                                    }
                                    selectNearestPoint(to: date)
                                }
                                .onEnded { _ in
                                    selectedPoint = nil
                                }
                        )
                }
            }
        }
    }

    private func selectNearestPoint(to date: Date) {
        guard let nearest = series.min(by: {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }) else { return }

        if selectedPoint?.id != nearest.id {
            selectedPoint = nearest
        }
    }
}

private struct ProgressCaption: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .scaledFont(12, weight: .bold, relativeTo: .caption)
                .foregroundStyle(.white.opacity(0.38))
            Text(value)
                .scaledFont(15, weight: .semibold, relativeTo: .subheadline)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProgressUnavailableCard: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .foregroundStyle(Color.brand)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .scaledFont(17, weight: .semibold, relativeTo: .body)
                    .foregroundStyle(.white)
                Text(message)
                    .scaledFont(15, relativeTo: .subheadline)
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: 20, strokeOpacity: 0.08)
    }
}

private struct Sparkline: View {
    let points: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let path = sparklinePath(size: size)
            ZStack {
                Rectangle()
                    .fill(Color.white.opacity(0.05))
                    .frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                path.stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func sparklinePath(size: CGSize) -> Path {
        guard !points.isEmpty else { return Path() }
        let minValue = points.min() ?? 0
        let maxValue = points.max() ?? minValue
        let span = max(maxValue - minValue, 1)
        let widthStep = points.count > 1 ? size.width / CGFloat(points.count - 1) : 0

        var path = Path()
        for (index, value) in points.enumerated() {
            let x = CGFloat(index) * widthStep
            let normalized = (value - minValue) / span
            let y = size.height - CGFloat(normalized) * size.height
            if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }
}

// MARK: - Progression data

enum ProgressRange: String, CaseIterable, Identifiable {
    case oneMonth
    case threeMonths
    case sixMonths
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .oneMonth: return "1M"
        case .threeMonths: return "3M"
        case .sixMonths: return "6M"
        case .all: return "All"
        }
    }

    var subtitle: String {
        switch self {
        case .oneMonth: return "Past month"
        case .threeMonths: return "Past 3 months"
        case .sixMonths: return "Past 6 months"
        case .all: return "All logged history"
        }
    }

    func cutoff(from now: Date = .now, calendar: Calendar = .current) -> Date? {
        switch self {
        case .oneMonth: return calendar.date(byAdding: .month, value: -1, to: now)
        case .threeMonths: return calendar.date(byAdding: .month, value: -3, to: now)
        case .sixMonths: return calendar.date(byAdding: .month, value: -6, to: now)
        case .all: return nil
        }
    }
}

struct ExerciseProgressPoint: Identifiable {
    let id: String
    let moveSlug: String
    let title: String
    let date: Date
    /// The move's metric kind — the same for every point in a move, decided by the
    /// latest session (see `ProgressionStats.exercisePoints`).
    let kind: MetricKind
    let unit: WeightUnit
    /// Raw top-set values, for the scrub readout. `weight` is in the display unit.
    let weight: Double
    let reps: Int?
    let seconds: Int?
    /// Metric values precomputed under `kind`, in the display unit.
    let intensity: Double
    let volume: Double
    let workoutId: String
    let workoutTitle: String
    let workoutMeta: String?

    func value(for mode: MetricMode) -> Double {
        mode == .intensity ? intensity : volume
    }

    /// A copy with `volume` replaced — lets the chart plot a day's summed volume
    /// while keeping a real session's date/identity for the scrub readout.
    func withVolume(_ newVolume: Double) -> ExerciseProgressPoint {
        ExerciseProgressPoint(id: id, moveSlug: moveSlug, title: title, date: date,
                              kind: kind, unit: unit, weight: weight, reps: reps,
                              seconds: seconds, intensity: intensity, volume: newVolume,
                              workoutId: workoutId, workoutTitle: workoutTitle,
                              workoutMeta: workoutMeta)
    }

    /// The secondary dimension behind a weighted point's est. max — i.e. the reps
    /// the estimate came from. Nil for bodyweight/timed, where the headline already
    /// *is* the reps/time and repeating it would be noise.
    var effortLabel: String? {
        guard kind == .weighted, let reps, reps > 0 else { return nil }
        return "\(reps) reps"
    }
}

struct ExerciseProgressSummary: Identifiable {
    let id: String
    let moveSlug: String
    let title: String
    let points: [ExerciseProgressPoint]

    /// A move has one kind, taken from its most recent session.
    var kind: MetricKind { latest.kind }
    var first: ExerciseProgressPoint { points[0] }
    var latest: ExerciseProgressPoint { points[points.count - 1] }

    /// Hero stats read off the same per-day collapse the chart plots, so the big
    /// number and Start/Best captions never disagree with the bar/line: in volume
    /// mode a day's sessions sum, in intensity mode a day keeps its best set (see
    /// `ProgressionStats.dailySeries`). For the common one-session-per-day case this
    /// is identical to reading the raw session points.
    private func daily(_ mode: MetricMode) -> [ExerciseProgressPoint] {
        ProgressionStats.dailySeries(points, mode: mode)
    }

    func best(_ mode: MetricMode) -> ExerciseProgressPoint {
        daily(mode).max { $0.value(for: mode) < $1.value(for: mode) } ?? latest
    }
    func delta(_ mode: MetricMode) -> Double {
        let series = daily(mode)
        guard let start = series.first, let end = series.last else { return 0 }
        return end.value(for: mode) - start.value(for: mode)
    }
    func isImproving(_ mode: MetricMode) -> Bool { delta(mode) >= 0 }

    // MARK: Formatting

    func headlineValue(_ mode: MetricMode) -> String { kind.valueText((daily(mode).last ?? latest).value(for: mode)) }
    func headlineUnit(_ mode: MetricMode) -> String? { kind.unitText(weightUnit: latest.unit) }
    func deltaLabel(_ mode: MetricMode) -> String {
        kind.deltaText(delta(mode), weightUnit: latest.unit)
    }

    func startLabel(_ mode: MetricMode) -> String { valueLabel((daily(mode).first ?? first).value(for: mode)) }
    func bestLabel(_ mode: MetricMode) -> String { valueLabel(best(mode).value(for: mode)) }
    var latestDateLabel: String { latest.date.formatted(date: .abbreviated, time: .omitted) }

    private func valueLabel(_ value: Double) -> String {
        let number = kind.valueText(value)
        guard let unit = kind.unitText(weightUnit: latest.unit) else { return number }
        return "\(number) \(unit)"
    }

    var contextLabel: String {
        let workoutCount = Set(points.map(\.workoutId)).count
        let entryCount = points.count
        let workouts = workoutCount == 1 ? "1 workout" : "\(workoutCount) workouts"
        let entries = entryCount == 1 ? "1 entry" : "\(entryCount) entries"
        return "\(entries) · \(workouts)"
    }
}

enum ProgressionStats {
    static func logs(_ logs: [WorkoutLog], in range: ProgressRange, now: Date = .now) -> [WorkoutLog] {
        guard let cutoff = range.cutoff(from: now) else { return logs }
        return logs.filter { $0.performedAt >= cutoff }
    }

    /// Moves whose latest in-range session is a genuine all-time best. A move counts
    /// only if the latest session's intensity strictly beats every session *before
    /// it across the move's entire history* — `allTimePoints` is the unfiltered
    /// history, so a range-scoped best that a higher out-of-range session already
    /// topped is not a PR (a trophy labeled "new PR" should mean a real record, not
    /// just the best of the viewing window). A move with no earlier session has
    /// nothing to beat and never counts.
    static func prCount(_ summaries: [ExerciseProgressSummary],
                        allTimePoints: [ExerciseProgressPoint]) -> Int {
        let historyByMove = Dictionary(grouping: allTimePoints, by: \.moveSlug)
        return summaries.filter { summary in
            let latest = summary.latest
            let priorBest = (historyByMove[summary.moveSlug] ?? [])
                .filter { $0.date < latest.date }
                .map(\.intensity)
                .max()
            guard let priorBest else { return false }
            return latest.intensity > priorBest
        }.count
    }

    /// Collapse points to one per calendar day for charting. Points already carry
    /// one session's aggregate, so this only merges the case where the same move was
    /// logged in *multiple* sessions on one day. The metrics merge differently:
    /// **intensity** keeps the day's best set (a real point, with its reps for the
    /// readout); **volume** — "total work" — sums the day's sessions rather than
    /// shadowing the smaller behind the larger, carried on the day's largest session
    /// so the scrub readout still names a real workout.
    static func dailySeries(_ points: [ExerciseProgressPoint], mode: MetricMode,
                            calendar: Calendar = .current) -> [ExerciseProgressPoint] {
        Dictionary(grouping: points) { calendar.startOfDay(for: $0.date) }
            .values
            .compactMap { day -> ExerciseProgressPoint? in
                switch mode {
                case .intensity:
                    return day.max { $0.intensity < $1.intensity }
                case .volume:
                    guard let representative = day.max(by: { $0.volume < $1.volume }) else { return nil }
                    return representative.withVolume(day.reduce(0) { $0 + $1.volume })
                }
            }
            .sorted { $0.date < $1.date }
    }

    @MainActor
    static func exerciseSummaries(logs: [WorkoutLog],
                                  catalog: CatalogStore,
                                  displayUnit: WeightUnit = .lb) -> [ExerciseProgressSummary] {
        let grouped = Dictionary(grouping: exercisePoints(logs: logs,
                                                          catalog: catalog,
                                                          displayUnit: displayUnit), by: \.moveSlug)
        return grouped.compactMap { moveSlug, points in
            let title = points.sorted { $0.date < $1.date }.last?.title ?? catalog.taxonomy.move(moveSlug)
            return exerciseSummary(moveSlug: moveSlug, title: title, points: points)
        }
        // Most-recently-performed first, so the moves you're currently training sit
        // on top; ties fall back to the busier move, then title for stability.
        .sorted {
            if $0.latest.date != $1.latest.date { return $0.latest.date > $1.latest.date }
            if $0.points.count != $1.points.count { return $0.points.count > $1.points.count }
            return $0.title < $1.title
        }
    }

    static func exerciseSummary(moveSlug: String,
                                title: String,
                                points: [ExerciseProgressPoint]) -> ExerciseProgressSummary? {
        let sorted = points.sorted { $0.date < $1.date }
        guard !sorted.isEmpty else { return nil }
        return ExerciseProgressSummary(id: moveSlug, moveSlug: moveSlug, title: title, points: sorted)
    }

    @MainActor
    static func exercisePoints(logs: [WorkoutLog],
                               moveSlug: String? = nil,
                               catalog: CatalogStore,
                               displayUnit: WeightUnit = .lb) -> [ExerciseProgressPoint] {
        // Gather each session's top set per move first: a move's metric kind depends
        // on its *latest* session, so we can't classify a point until we've seen the
        // whole move's history.
        struct RawEntry {
            let title: String
            let date: Date
            let topSet: SetEntry
            let sets: [SetEntry]
            let idSeed: String
            let workoutId: String
            let workoutTitle: String
            let workoutMeta: String?
        }
        var rawByMove: [String: [RawEntry]] = [:]
        for log in logs {
            let workout = catalog.workout(id: log.workoutId)
            let workoutId = workout?.id ?? log.workoutId
            let workoutTitle = workout?.title ?? "Unavailable workout"
            let workoutMeta = workout.map { Self.workoutMeta($0, taxonomy: catalog.taxonomy) }
            for entry in log.moveEntries {
                guard let key = progressionKey(for: entry) else { continue }
                if let moveSlug, key != moveSlug { continue }
                guard let topSet = entry.topSet else { continue }
                rawByMove[key, default: []].append(
                    RawEntry(title: progressionTitle(for: entry, catalog: catalog),
                             date: log.performedAt,
                             topSet: topSet,
                             sets: entry.orderedSets,
                             idSeed: "\(log.id.uuidString)-\(key)-\(entry.label)-\(topSet.weightValue)-\(topSet.order)",
                             workoutId: workoutId,
                             workoutTitle: workoutTitle,
                             workoutMeta: workoutMeta))
            }
        }

        var points: [ExerciseProgressPoint] = []
        for (key, raws) in rawByMove {
            let ordered = raws.sorted { $0.date < $1.date }
            guard let latest = ordered.last else { continue }
            let kind = MetricKind.classify(topSet: latest.topSet)
            for raw in ordered {
                // The point's representative set is the one that maximizes this kind's
                // intensity (best Epley for weighted), not `topSet`'s heaviest-raw-weight
                // pick — so the headline number, PR marker, and effort-label reps all
                // describe the same set.
                let peak = kind.peakSet(in: raw.sets, displayUnit: displayUnit) ?? raw.topSet
                let weight = peak.weightUnit.convertedWeight(peak.weightValue, to: displayUnit)
                points.append(
                    ExerciseProgressPoint(id: raw.idSeed,
                                          moveSlug: key,
                                          title: raw.title,
                                          date: raw.date,
                                          kind: kind,
                                          unit: displayUnit,
                                          weight: weight,
                                          reps: peak.reps,
                                          seconds: peak.seconds,
                                          intensity: kind.intensity(of: peak, displayUnit: displayUnit),
                                          volume: kind.volume(sets: raw.sets, displayUnit: displayUnit),
                                          workoutId: raw.workoutId,
                                          workoutTitle: raw.workoutTitle,
                                          workoutMeta: raw.workoutMeta))
            }
        }
        return points.sorted { $0.date < $1.date }
    }

    private static func workoutMeta(_ workout: Workout, taxonomy: Taxonomy) -> String {
        var parts: [String] = []
        if let episode = workout.episode { parts.append("Ep \(episode)") }
        parts.append(workout.durationLabel)
        parts.append(taxonomy.bodyFocus(workout.facets.bodyFocus))
        return parts.joined(separator: "  •  ")
    }

    static func progressionKey(for entry: MoveEntry) -> String? {
        if let slug = entry.moveSlug, !slug.isEmpty { return slug }
        let normalized = entry.label
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        guard !normalized.isEmpty else { return nil }
        return "custom:\(normalized)"
    }

    @MainActor
    private static func progressionTitle(for entry: MoveEntry, catalog: CatalogStore) -> String {
        let label = entry.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !label.isEmpty { return label }
        if let slug = entry.moveSlug { return catalog.taxonomy.move(slug) }
        return "Custom Exercise"
    }
}
