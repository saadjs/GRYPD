import SwiftUI
import SwiftData

/// Log or edit a workout session using the Apple Fitness "Add Workout" sheet style:
/// a large title, a stack of dark cards, and native toolbar actions. All inputs
/// are system controls (no custom button shapes), surfaces come from the shared
/// design system, and type uses the scaled-font roles.
struct LogSessionView: View {
    /// The matched catalog workout, if known. Nil when editing a session whose
    /// workout has left the catalog, or a not-yet-matched Health import.
    private let workout: Workout?
    /// The session being edited, or nil when creating a new one.
    private let editingLog: WorkoutLog?

    @Environment(CatalogStore.self) private var catalog
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("defaultUnit") private var defaultUnitRaw = WeightUnit.lb.rawValue
    @AppStorage(DumbbellDefaults.keyLight) private var dumbbellLight = DumbbellDefaults.defaultLight
    @AppStorage(DumbbellDefaults.keyMedium) private var dumbbellMedium = DumbbellDefaults.defaultMedium
    @AppStorage(DumbbellDefaults.keyHeavy) private var dumbbellHeavy = DumbbellDefaults.defaultHeavy

    @State private var performedAt = Date.now
    @State private var activeCalories: Int = 0
    @State private var note = ""
    @State private var entries: [LogExerciseDraft] = []
    @State private var didSeed = false
    @State private var showingMovePicker = false
    @State private var activeSetPicker: SetPickerTarget?
    /// Measured height of one exercise row, plus one added set. The embedded
    /// List scrolls natively for deletion but is height-pinned inside the sheet.
    @State private var measuredBaseRowHeight: CGFloat = 0
    @State private var measuredTwoSetRowHeight: CGFloat = 0

    @ScaledMetric(relativeTo: .body) private var rowMinHeight: CGFloat = 54
    /// Fallback per-row height used only until `measuredRowHeight` is known. Scaled
    /// so an un-measured first frame is still roughly right at any Dynamic Type size.
    @ScaledMetric(relativeTo: .body) private var exerciseRowHeight: CGFloat = 72
    @ScaledMetric(relativeTo: .body) private var valueButtonMinHeight: CGFloat = 40
    @ScaledMetric(relativeTo: .body) private var wheelSheetHeight: CGFloat = 230

    /// `listRowInsets` top + bottom applied to each exercise row (see the List).
    private let exerciseRowInset: CGFloat = 10

    private var defaultUnit: WeightUnit { WeightUnit(rawValue: defaultUnitRaw) ?? .lb }
    private var dumbbellDefaults: DumbbellDefaults {
        DumbbellDefaults(light: dumbbellLight, medium: dumbbellMedium,
                         heavy: dumbbellHeavy, unit: defaultUnit)
    }

    /// Create a new session for a catalog workout.
    init(workout: Workout) {
        self.workout = workout
        self.editingLog = nil
    }

    /// Edit an existing session. `workout` is its matched catalog workout, if
    /// still available — pass nil for an unavailable or unmatched session.
    init(editing log: WorkoutLog, workout: Workout?) {
        self.workout = workout
        self.editingLog = log
    }

    private var isEditing: Bool { editingLog != nil }
    private var titleText: String { isEditing ? "Edit Session" : "Add Workout" }
    private var durationLabel: String {
        let minutes = workout?.durationMinutes
        guard let minutes, minutes > 0 else { return "—" }
        return "\(minutes)min"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        workoutCard
                        durationCard
                        activeCaloriesCard
                        weightsCard
                        noteCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 48)
                }
            }
            .navigationTitle(titleText)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { save() } label: {
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
        .onAppear(perform: seed)
        .sheet(isPresented: $showingMovePicker) {
            MovePickerView(taxonomy: catalog.taxonomy,
                           excluded: Set(entries.compactMap(\.moveSlug))) { slug, label in
                addMove(slug: slug, label: label)
            }
            .sheetPresentation()
        }
        .sheet(item: $activeSetPicker) { target in
            setPickerSheet(target)
                .sheetPresentation()
        }
    }

    // MARK: - Cards

    private var workoutCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.brand)
            Text("Workout")
                .primaryLabelFont(weight: .semibold)
                .foregroundStyle(.white)
            Spacer(minLength: 12)
            Text(workout?.title ?? "Unknown workout")
                .scaledFont(15, weight: .medium, relativeTo: .subheadline)
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
        }
        .padding(16)
        .frame(minHeight: rowMinHeight)
        .cardSurface()
    }

    private var durationCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "clock")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.brand)
                Text("Duration")
                    .primaryLabelFont(weight: .semibold)
                    .foregroundStyle(.white)
                Spacer(minLength: 12)
                Text(durationLabel)
                    .scaledFont(15, weight: .medium, relativeTo: .subheadline)
                    .foregroundStyle(.white.opacity(0.55))
            }

            Divider()
                .background(Color.white.opacity(0.08))

            HStack(spacing: 14) {
                Text("Start")
                    .primaryLabelFont()
                    .foregroundStyle(.white)
                Spacer(minLength: 12)
                HStack(spacing: 8) {
                    datePickerControl(.date)
                    datePickerControl(.hourAndMinute)
                }
            }
        }
        .padding(16)
        .cardSurface()
    }

    private func datePickerControl(_ components: DatePickerComponents) -> some View {
        DatePicker("", selection: $performedAt, displayedComponents: components)
            .labelsHidden()
            .datePickerStyle(.compact)
            .scaledFont(15, weight: .semibold, relativeTo: .subheadline)
    }

    private var activeCaloriesCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "flame.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.brand)
                Text("Active Calories")
                    .primaryLabelFont(weight: .semibold)
                    .foregroundStyle(.white)
                Spacer(minLength: 12)
                Picker("", selection: $activeCalories) {
                    ForEach(Array(stride(from: 0, through: 2000, by: 5)), id: \.self) { value in
                        Text("\(value) cal").tag(value)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)
                .scaledFont(15, weight: .semibold, relativeTo: .subheadline)
                .accessibilityLabel("Active Calories")
            }

            Text("Optional. Enter the active calories from your workout if you tracked them.")
                .scaledFont(14, weight: .medium, relativeTo: .subheadline)
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .cardSurface()
    }

    private var weightsCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "dumbbell")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.brand)
                Text("Sets")
                    .primaryLabelFont(weight: .semibold)
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                if !entries.isEmpty {
                    Text("\(entries.count)")
                        .scaledFont(15, weight: .bold, relativeTo: .subheadline)
                        .foregroundStyle(Color.brand)
                        .accessibilityLabel("\(entries.count) exercises")
                }
            }

            if entries.isEmpty {
                Text("Add exercises to log set-by-set weight, reps, and time. Each exercise is a catalog move, so its history shows up on Progress. Leave empty to log just the session.")
                    .scaledFont(14, weight: .medium, relativeTo: .subheadline)
                    .foregroundStyle(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                List {
                    ForEach($entries) { $entry in
                        weightRow($entry)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
                    }
                    .onDelete(perform: deleteExercises)
                    .onMove(perform: moveExercises)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .frame(height: exerciseListHeight)
                .background(alignment: .top) { rowHeightProbes }
            }

            Button {
                showingMovePicker = true
            } label: {
                Label("Add Exercise", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(.brand)
            .foregroundStyle(Color.onBrand)
            .scaledFont(15, weight: .semibold, relativeTo: .subheadline)
        }
        .padding(16)
        .cardSurface()
    }

    /// Exact height for the embedded exercise List, accounting for variable set
    /// counts per move. Falls back to a scaled estimate until probes report.
    private var exerciseListHeight: CGFloat {
        let base = measuredBaseRowHeight > 0 ? measuredBaseRowHeight : exerciseRowHeight
        let extra = measuredTwoSetRowHeight > measuredBaseRowHeight
            ? measuredTwoSetRowHeight - measuredBaseRowHeight
            : exerciseRowHeight * 0.55
        return entries.reduce(CGFloat(0)) { total, entry in
            total + base + max(0, CGFloat(entry.sets.count - 1)) * extra + exerciseRowInset
        }
    }

    private var rowHeightProbes: some View {
        VStack {
            weightRow(.constant(LogExerciseDraft(moveSlug: nil,
                                                 label: "Probe",
                                                 sets: [SetDraft()])))
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measuredBaseRowHeight = $0 }
            weightRow(.constant(LogExerciseDraft(moveSlug: nil,
                                                 label: "Probe",
                                                 sets: [SetDraft(),
                                                        SetDraft()])))
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measuredTwoSetRowHeight = $0 }
        }
        .fixedSize(horizontal: false, vertical: true)
        .hidden()
        .allowsHitTesting(false)
    }

    /// One move row. Swipe left deletes the whole move; the nested remove button
    /// deletes one set without fighting List's native gesture.
    private func weightRow(_ entry: Binding<LogExerciseDraft>) -> some View {
        let name = entry.wrappedValue.trimmedLabel.isEmpty ? "Exercise" : entry.wrappedValue.trimmedLabel
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                exerciseName(name).frame(maxWidth: .infinity, alignment: .leading)
                Text(setCountLabel(entry.wrappedValue.sets.count))
                    .scaledFont(13, weight: .bold, relativeTo: .caption)
                    .foregroundStyle(Color.brand)
                // Decorative hint that the row is a drag source; the whole row
                // reorders via the List's native long-press drag.
                Image(systemName: "line.3.horizontal")
                    .scaledFont(13, weight: .semibold, relativeTo: .caption)
                    .foregroundStyle(.white.opacity(0.3))
                    .accessibilityHidden(true)
            }

            ForEach(entry.sets.indices, id: \.self) { index in
                setRow(entry: entry, index: index, name: name)
            }

            Button {
                addSet(to: entry)
            } label: {
                Label("Add Set", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(.brand)
            .scaledFont(14, weight: .semibold, relativeTo: .subheadline)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: AppRadius.card, fillOpacity: 0.05, strokeOpacity: 0.09)
    }

    private func exerciseName(_ name: String) -> some View {
        Text(name)
            .scaledFont(16, weight: .semibold, relativeTo: .body)
            .foregroundStyle(.white)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    @ViewBuilder
    private func setRow(entry: Binding<LogExerciseDraft>, index: Int, name: String) -> some View {
        let set = entry.sets[index]
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Set \(index + 1)")
                    .scaledFont(13, weight: .bold, relativeTo: .caption)
                    .foregroundStyle(.white.opacity(0.5))
                Spacer(minLength: 8)
                Button {
                    removeSet(from: entry, at: index)
                } label: {
                    Image(systemName: "minus.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.45))
                .accessibilityLabel("Remove set \(index + 1)")
                .disabled(entry.wrappedValue.sets.count <= 1)
                .opacity(entry.wrappedValue.sets.count <= 1 ? 0.35 : 1)
            }

            HStack(spacing: 6) {
                valueButton(title: "Weight",
                            value: weightLabel(set.wrappedValue.weight),
                            systemImage: "dumbbell") {
                    activeSetPicker = SetPickerTarget(entryID: entry.wrappedValue.id,
                                                      setID: set.wrappedValue.id,
                                                      kind: .weight)
                }
                valueButton(title: "Reps",
                            value: repsLabel(set.wrappedValue.reps),
                            systemImage: "number") {
                    activeSetPicker = SetPickerTarget(entryID: entry.wrappedValue.id,
                                                      setID: set.wrappedValue.id,
                                                      kind: .reps)
                }
                valueButton(title: "Timer",
                            value: timerLabel(set.wrappedValue.seconds),
                            systemImage: "timer") {
                    activeSetPicker = SetPickerTarget(entryID: entry.wrappedValue.id,
                                                      setID: set.wrappedValue.id,
                                                      kind: .timer)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 4)
    }

    private func valueButton(title: String,
                             value: String,
                             systemImage: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .scaledFont(11, weight: .semibold, relativeTo: .caption)
                Text(value)
                    .scaledFont(14, weight: .bold, relativeTo: .subheadline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, minHeight: valueButtonMinHeight)
            .padding(.horizontal, 2)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 8))
        .tint(.white.opacity(0.22))
        .foregroundStyle(.white)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }

    private func setPickerSheet(_ target: SetPickerTarget) -> some View {
        NavigationStack {
            Group {
                if let set = setBinding(entryID: target.entryID, setID: target.setID) {
                    VStack(spacing: 18) {
                        Text(target.kind.title)
                            .sectionHeaderFont()
                            .foregroundStyle(.white)
                        pickerContent(for: target.kind, set: set)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.ignoresSafeArea())
                } else {
                    ContentUnavailableView("Set unavailable", systemImage: "exclamationmark.triangle")
                        .background(Color.black.ignoresSafeArea())
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { activeSetPicker = nil }
                        .foregroundStyle(Color.brand)
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationBackground(.black)
    }

    @ViewBuilder
    private func pickerContent(for kind: SetPickerKind, set: Binding<SetDraft>) -> some View {
        switch kind {
        case .weight:
            Picker("Weight", selection: set.weight) {
                Text("—").tag(Optional<Double>.none)
                ForEach(weightValues, id: \.self) { value in
                    Text(weightLabel(value)).tag(Optional(value))
                }
            }
            .pickerStyle(.wheel)
            .frame(height: wheelSheetHeight)
            .clipped()
        case .reps:
            Picker("Reps", selection: set.reps) {
                Text("—").tag(Optional<Int>.none)
                ForEach(1...40, id: \.self) { value in
                    Text("\(value)").tag(Optional(value))
                }
            }
            .pickerStyle(.wheel)
            .frame(height: wheelSheetHeight)
            .clipped()
        case .timer:
            Picker("Timer", selection: set.seconds) {
                Text("—").tag(Optional<Int>.none)
                ForEach(Array(stride(from: 20, through: 120, by: 5)), id: \.self) { seconds in
                    Text(timerLabel(seconds)).tag(Optional(seconds))
                }
            }
            .pickerStyle(.wheel)
            .frame(height: wheelSheetHeight)
            .clipped()
        }
    }

    private func setBinding(entryID: UUID, setID: UUID) -> Binding<SetDraft>? {
        guard let entryIndex = entries.firstIndex(where: { $0.id == entryID }),
              let setIndex = entries[entryIndex].sets.firstIndex(where: { $0.id == setID }) else {
            return nil
        }
        return $entries[entryIndex].sets[setIndex]
    }

    private var weightValues: [Double] {
        DumbbellDefaults.options(for: defaultUnit)
    }

    private func weightLabel(_ value: Double?) -> String {
        guard let value, value > 0 else { return "—" }
        return "\(formatted(value)) \(defaultUnit.label)"
    }

    private func repsLabel(_ value: Int?) -> String {
        guard let value, value > 0 else { return "—" }
        return "\(value)"
    }

    private func timerLabel(_ value: Int?) -> String {
        guard let value, value > 0 else { return "—" }
        return timerLabel(value)
    }

    private func timerLabel(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds)s" : "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "text.alignleft")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.brand)
                Text("Note")
                    .primaryLabelFont(weight: .semibold)
                    .foregroundStyle(.white)
                Spacer(minLength: 12)
            }

            TextField("How did it feel?", text: $note, axis: .vertical)
                .lineLimit(1...4)
                .primaryLabelFont()
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(16)
        .cardSurface()
    }

    // MARK: - Lifecycle

    private func seed() {
        guard !didSeed else { return }
        didSeed = true
        if let log = editingLog {
            performedAt = log.performedAt
            activeCalories = log.activeEnergyKcal.map { Int($0.rounded()) } ?? 0
            note = log.note ?? ""
        }
        entries = draftEntries()
    }

    private func draftEntries() -> [LogExerciseDraft] {
        LogExerciseDrafts.make(workoutMoves: workout?.displayMoves ?? [],
                               existing: editingLog?.orderedMoveEntries ?? [],
                               defaultUnit: defaultUnit,
                               dumbbellDefaults: dumbbellDefaults,
                               moveLabel: catalog.taxonomy.move)
    }

    /// Append a catalog move chosen in the picker. Guarding on slug keeps a move
    /// from being added twice; the picker already excludes added slugs, this just
    /// makes the invariant local.
    private func addMove(slug: String, label: String) {
        guard !entries.contains(where: { $0.moveSlug == slug }) else { return }
        entries.append(LogExerciseDraft(moveSlug: slug, label: label,
                                        sets: [SetDraft(weight: dumbbellDefaults.weight(forMoveSlug: slug),
                                                        reps: nil,
                                                        seconds: nil)]))
    }

    private func deleteExercises(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
    }

    /// Reorder via the List's native long-press drag. `entries` is the save
    /// source of truth, so its new order is persisted as each move's `order`.
    private func moveExercises(from offsets: IndexSet, to destination: Int) {
        entries.move(fromOffsets: offsets, toOffset: destination)
    }

    private func addSet(to entry: Binding<LogExerciseDraft>) {
        let seed = entry.wrappedValue.sets.last
        entry.wrappedValue.sets.append(SetDraft(weight: seed?.weight,
                                                reps: seed?.reps,
                                                seconds: seed?.seconds))
    }

    private func removeSet(from entry: Binding<LogExerciseDraft>, at index: Int) {
        guard entry.wrappedValue.sets.indices.contains(index),
              entry.wrappedValue.sets.count > 1 else { return }
        entry.wrappedValue.sets.remove(at: index)
    }

    private func setCountLabel(_ count: Int) -> String {
        count == 1 ? "1 set" : "\(count) sets"
    }

    private func save() {
        let log = editingLog ?? WorkoutLog(workoutId: workout?.id ?? "",
                                           performedAt: performedAt,
                                           note: note.isEmpty ? nil : note)
        if editingLog == nil { context.insert(log) }

        log.performedAt = performedAt
        log.activeEnergyKcal = activeCalories > 0 ? Double(activeCalories) : nil
        log.note = note.isEmpty ? nil : note

        // Rebuild move entries from the drafts: delete-and-recreate is simple and
        // correct whether we're creating fresh or editing an existing session.
        for old in log.moveEntries { context.delete(old) }
        log.moveEntries.removeAll()
        for (order, e) in entries.enumerated() where e.shouldPersist {
            let m = MoveEntry(moveSlug: e.moveSlug, label: e.trimmedLabel)
            m.order = order
            m.log = log
            log.moveEntries.append(m)
            context.insert(m)
            for (index, setDraft) in e.sets.enumerated() where !setDraft.isEmpty {
                let set = SetEntry(order: index,
                                   weightValue: setDraft.weight ?? 0,
                                   weightUnit: defaultUnit,
                                   reps: setDraft.reps,
                                   seconds: setDraft.seconds)
                set.moveEntry = m
                m.sets.append(set)
                context.insert(set)
            }
        }
        dismiss()
    }
}

private struct SetPickerTarget: Identifiable, Equatable {
    let entryID: UUID
    let setID: UUID
    let kind: SetPickerKind

    var id: String {
        "\(entryID.uuidString)-\(setID.uuidString)-\(kind.rawValue)"
    }
}

private enum SetPickerKind: String, Equatable {
    case weight
    case reps
    case timer

    var title: String {
        switch self {
        case .weight: return "Weight"
        case .reps: return "Reps"
        case .timer: return "Timer"
        }
    }
}
