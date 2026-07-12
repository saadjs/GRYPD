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
    @State private var showingMissingEffort = false

    @ScaledMetric(relativeTo: .body) private var rowMinHeight: CGFloat = 54
    @ScaledMetric(relativeTo: .body) private var valueButtonMinHeight: CGFloat = 40
    @ScaledMetric(relativeTo: .body) private var wheelSheetHeight: CGFloat = 230

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
                           logged: Set(entries.compactMap(\.moveSlug))) { slug, label in
                addMove(slug: slug, label: label)
            }
            .sheetPresentation()
        }
        .sheet(item: $activeSetPicker) { target in
            setPickerSheet(target)
                .sheetPresentation()
        }
        .alert("Add Set Effort", isPresented: $showingMissingEffort) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("For each weighted exercise, rate your last set by choosing how many more good reps you could have done.")
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
                VStack(spacing: 10) {
                    ForEach($entries) { $entry in
                        let index = entries.firstIndex { $0.id == entry.id }
                        weightRow($entry, index: index, count: entries.count)
                    }
                }
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

    /// One move row. A plain (non-List) row so the card grows to fit all
    /// exercises and sets instead of clipping when the content is tall.
    /// Reordering and whole-exercise deletion use explicit buttons since this
    /// isn't a List and so can't offer swipe-to-delete or drag-to-reorder.
    private func weightRow(_ entry: Binding<LogExerciseDraft>, index: Int?, count: Int) -> some View {
        let entryID = entry.wrappedValue.id
        let name = entry.wrappedValue.trimmedLabel.isEmpty ? "Exercise" : entry.wrappedValue.trimmedLabel
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                exerciseName(name).frame(maxWidth: .infinity, alignment: .leading)
                Text(setCountLabel(entry.wrappedValue.sets.count))
                    .scaledFont(13, weight: .bold, relativeTo: .caption)
                    .foregroundStyle(Color.brand)
            }

            HStack(spacing: 0) {
                Button {
                    moveExercise(id: entryID, by: -1)
                } label: {
                    Image(systemName: "chevron.up")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .disabled(index == nil || index == 0)
                .opacity(index == 0 ? 0.3 : 1)
                .accessibilityLabel("Move \(name) up")

                Button {
                    moveExercise(id: entryID, by: 1)
                } label: {
                    Image(systemName: "chevron.down")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .disabled(index == nil || index == count - 1)
                .opacity(index == count - 1 ? 0.3 : 1)
                .accessibilityLabel("Move \(name) down")

                Button {
                    deleteExercise(id: entryID)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Remove \(name)")
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .buttonStyle(.plain)
            .scaledFont(13, weight: .semibold, relativeTo: .caption)
            .foregroundStyle(.white.opacity(0.45))

            ForEach(entry.sets.indices, id: \.self) { index in
                setRow(entry: entry, index: index, name: name)
            }

            if entry.wrappedValue.sets.contains(where: isWeightedRepSet) {
                valueButton(title: "Last set effort",
                            value: effortLabel(entry.wrappedValue.lastSetRepsInReserve),
                            systemImage: "gauge.with.dots.needle.67percent") {
                    activeSetPicker = SetPickerTarget(entryID: entry.wrappedValue.id,
                                                      setID: entry.wrappedValue.id,
                                                      kind: .effort)
                }
                Text("Rate your last set · How many more good reps could you do?")
                    .scaledFont(12, weight: .medium, relativeTo: .caption)
                    .foregroundStyle(.white.opacity(0.45))
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
                if target.kind == .effort,
                   let effort = effortBinding(entryID: target.entryID) {
                    VStack(spacing: 18) {
                        Text(target.kind.title)
                            .sectionHeaderFont()
                            .foregroundStyle(.white)
                        effortPicker(selection: effort)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.ignoresSafeArea())
                } else if let set = setBinding(entryID: target.entryID, setID: target.setID) {
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
        case .effort:
            EmptyView()
        }
    }

    private func effortPicker(selection: Binding<Int?>) -> some View {
        Picker("Reps in reserve", selection: selection) {
            Text("Choose effort").tag(Optional<Int>.none)
            ForEach(0...4, id: \.self) { value in
                Text(effortOptionLabel(value)).tag(Optional(value))
            }
        }
        .pickerStyle(.wheel)
        .frame(height: wheelSheetHeight)
        .clipped()
    }

    private func effortBinding(entryID: UUID) -> Binding<Int?>? {
        guard let entryIndex = entries.firstIndex(where: { $0.id == entryID }) else { return nil }
        return Binding(
            get: { entries[entryIndex].lastSetRepsInReserve },
            set: { entries[entryIndex].setLastSetRepsInReserve($0) }
        )
    }

    private func setBinding(entryID: UUID, setID: UUID) -> Binding<SetDraft>? {
        guard let entryIndex = entries.firstIndex(where: { $0.id == entryID }),
              let setIndex = entries[entryIndex].sets.firstIndex(where: { $0.id == setID }) else {
            return nil
        }
        return Binding(
            get: { entries[entryIndex].sets[setIndex] },
            set: {
                entries[entryIndex].sets[setIndex] = $0
                entries[entryIndex].reconcileLastSetEffort()
            }
        )
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

    private func effortLabel(_ value: Int?) -> String {
        guard let value else { return "Choose effort" }
        return effortOptionLabel(value)
    }

    private func effortOptionLabel(_ value: Int) -> String {
        switch value {
        case 0: return "Max effort · 0 more"
        case 1: return "1 more rep"
        case 2: return "2 more reps"
        case 3: return "3 more reps"
        default: return "4+ more reps"
        }
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

    private func deleteExercise(id: LogExerciseDraft.ID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries.remove(at: index)
    }

    /// Reorder via the row's up/down buttons. `entries` is the save source of
    /// truth, so its new order is persisted as each move's `order`.
    private func moveExercise(id: LogExerciseDraft.ID, by delta: Int) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let destination = index + delta
        guard entries.indices.contains(destination) else { return }
        entries.swapAt(index, destination)
    }

    private func addSet(to entry: Binding<LogExerciseDraft>) {
        let seed = entry.wrappedValue.sets.last
        entry.wrappedValue.sets.append(SetDraft(weight: seed?.weight,
                                                reps: seed?.reps,
                                                seconds: seed?.seconds))
        entry.wrappedValue.setLastSetRepsInReserve(nil)
    }

    private func removeSet(from entry: Binding<LogExerciseDraft>, at index: Int) {
        guard entry.wrappedValue.sets.indices.contains(index),
              entry.wrappedValue.sets.count > 1 else { return }
        entry.wrappedValue.sets.remove(at: index)
        entry.wrappedValue.reconcileLastSetEffort()
    }

    private func setCountLabel(_ count: Int) -> String {
        count == 1 ? "1 set" : "\(count) sets"
    }

    private func save() {
        guard !hasWeightedSetMissingEffort else {
            showingMissingEffort = true
            return
        }

        let log = editingLog ?? WorkoutLog(workoutId: workout?.id ?? "",
                                           performedAt: performedAt,
                                           note: note.isEmpty ? nil : note)
        if editingLog == nil { context.insert(log) }

        log.performedAt = performedAt
        log.activeEnergyKcal = activeCalories > 0 ? Double(activeCalories) : nil
        log.note = note.isEmpty ? nil : note
        if let workout {
            // Preserve the catalog classification on the log so future catalog
            // refreshes cannot move an existing session between goal buckets.
            log.bodyFocus = WorkoutBodyFocus(rawValue: workout.facets.bodyFocus)
        }

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
            let lastWeightedSetID = e.sets.last(where: isWeightedRepSet)?.id
            for (index, setDraft) in e.sets.enumerated() where !setDraft.isEmpty {
                let set = SetEntry(order: index,
                                   weightValue: setDraft.weight ?? 0,
                                   weightUnit: defaultUnit,
                                   reps: setDraft.reps,
                                   repsInReserve: setDraft.id == lastWeightedSetID
                                    ? e.lastSetRepsInReserve
                                    : nil,
                                   seconds: setDraft.seconds)
                set.moveEntry = m
                m.sets.append(set)
                context.insert(set)
            }
        }
        dismiss()
    }

    private var hasWeightedSetMissingEffort: Bool {
        entries.contains { entry in
            entry.sets.contains(where: isWeightedRepSet)
                && entry.lastSetRepsInReserve == nil
        }
    }

    private func isWeightedRepSet(_ set: SetDraft) -> Bool {
        (set.weight ?? 0) > 0 && (set.reps ?? 0) > 0
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
    case effort

    var title: String {
        switch self {
        case .weight: return "Weight"
        case .reps: return "Reps"
        case .timer: return "Timer"
        case .effort: return "How Did This Set Feel?"
        }
    }
}
