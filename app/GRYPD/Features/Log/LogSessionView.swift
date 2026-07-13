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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("defaultUnit") private var defaultUnitRaw = WeightUnit.lb.rawValue
    @AppStorage(DumbbellDefaults.keyLight) private var dumbbellLight = DumbbellDefaults.defaultLight
    @AppStorage(DumbbellDefaults.keyMedium) private var dumbbellMedium = DumbbellDefaults.defaultMedium
    @AppStorage(DumbbellDefaults.keyHeavy) private var dumbbellHeavy = DumbbellDefaults.defaultHeavy

    @State private var performedAt = Date.now
    @State private var activeCalories: Int?
    @State private var note = ""
    @State private var entries: [LogExerciseDraft] = []
    @State private var initialEntries: [LogExerciseDraft] = []
    @State private var initialPerformedAt = Date.now
    @State private var didSeed = false
    @State private var showingMovePicker = false
    @State private var showingDiscardConfirmation = false
    @State private var pendingExerciseDeletion: LogExerciseDraft.ID?
    @FocusState private var isNumericFieldFocused: Bool

    @ScaledMetric(relativeTo: .body) private var rowMinHeight: CGFloat = 54
    @ScaledMetric(relativeTo: .body) private var fieldMinHeight: CGFloat = 44

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
                    Button("Cancel", action: cancel)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Save", action: save)
                        .foregroundStyle(Color.brand)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isNumericFieldFocused = false
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheetPresentation()
        .presentationBackground(.black)
        .interactiveDismissDisabled(hasEnteredData)
        .onAppear(perform: seed)
        .sheet(isPresented: $showingMovePicker) {
            MovePickerView(taxonomy: catalog.taxonomy,
                           logged: Set(entries.compactMap(\.moveSlug))) { slug, label in
                addMove(slug: slug, label: label)
            }
            .sheetPresentation()
        }
        .confirmationDialog("Discard this workout log?",
                            isPresented: $showingDiscardConfirmation,
                            titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("Your entered sets and session details will be lost.")
        }
        .confirmationDialog("Remove this exercise?",
                            isPresented: Binding(
                                get: { pendingExerciseDeletion != nil },
                                set: { if !$0 { pendingExerciseDeletion = nil } }
                            ),
                            titleVisibility: .visible) {
            Button("Remove Exercise", role: .destructive) { confirmExerciseDeletion() }
            Button("Cancel", role: .cancel) { pendingExerciseDeletion = nil }
        } message: {
            Text("All entered sets for this exercise will be removed.")
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

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Start").primaryLabelFont().foregroundStyle(.white)
                    datePickerControl(.date)
                    datePickerControl(.hourAndMinute)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 14) {
                    Text("Start").primaryLabelFont().foregroundStyle(.white)
                    Spacer(minLength: 12)
                    HStack(spacing: 8) {
                        datePickerControl(.date)
                        datePickerControl(.hourAndMinute)
                    }
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
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    activeCaloriesLabel
                    activeCaloriesField
                }
            } else {
                HStack(spacing: 14) {
                    activeCaloriesLabel
                    Spacer(minLength: 12)
                    activeCaloriesField
                }
            }

            Text("Optional. Enter the active calories from your workout if you tracked them.")
                .scaledFont(14, weight: .medium, relativeTo: .subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .cardSurface()
    }

    private var activeCaloriesLabel: some View {
        HStack(spacing: 14) {
                Image(systemName: "flame.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.brand)
                Text("Active Calories")
                    .primaryLabelFont(weight: .semibold)
                    .foregroundStyle(.white)
        }
    }

    private var activeCaloriesField: some View {
        TextField("Optional", value: $activeCalories, format: .number)
            .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
            .keyboardType(.numberPad)
            .focused($isNumericFieldFocused)
            .scaledFont(15, weight: .semibold, relativeTo: .subheadline)
            .accessibilityLabel("Active Calories")
            .accessibilityHint("Optional. Enter active calories burned.")
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
                VStack(spacing: 8) {
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
    /// Reordering and deletion live in the native header menu. They are useful
    /// but infrequent commands, so they shouldn't consume a dedicated row in
    /// every exercise card.
    private func weightRow(_ entry: Binding<LogExerciseDraft>, index: Int?, count: Int) -> some View {
        let entryID = entry.wrappedValue.id
        let name = entry.wrappedValue.trimmedLabel.isEmpty ? "Exercise" : entry.wrappedValue.trimmedLabel
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                exerciseName(name).frame(maxWidth: .infinity, alignment: .leading)
                Text(setCountLabel(entry.wrappedValue.sets.count))
                    .scaledFont(13, weight: .bold, relativeTo: .caption)
                    .foregroundStyle(Color.brand)
                Menu {
                    Button {
                        moveExercise(id: entryID, by: -1)
                    } label: {
                        Label("Move Up", systemImage: "arrow.up")
                    }
                    .disabled(index == nil || index == 0)

                    Button {
                        moveExercise(id: entryID, by: 1)
                    } label: {
                        Label("Move Down", systemImage: "arrow.down")
                    }
                    .disabled(index == nil || index == count - 1)

                    Divider()

                    Button(role: .destructive) {
                        requestExerciseDeletion(id: entryID)
                    } label: {
                        Label("Remove Exercise", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Actions for \(name)")
                .tint(.secondary)
            }

            ForEach(entry.sets.indices, id: \.self) { index in
                setRow(entry: entry, index: index, name: name)
            }

            if entry.wrappedValue.sets.contains(where: isWeightedRepSet) {
                Picker("Last set effort (optional)",
                       selection: effortBinding(for: entry)) {
                    Text("Not recorded").tag(Optional<Int>.none)
                    ForEach(0...4, id: \.self) { value in
                        Text(effortOptionLabel(value)).tag(Optional(value))
                    }
                }
                .pickerStyle(.menu)
                .tint(.brand)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
        let set = reconciledSetBinding(entry: entry, index: index)
        VStack(alignment: .leading, spacing: 6) {
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

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { setFields(set: set, exercise: name, number: index + 1) }
                VStack(spacing: 8) { setFields(set: set, exercise: name, number: index + 1) }
            }

        }
        .padding(.vertical, 1)
    }

    /// Keep the effort rating tied to the weighted set the user rated. Direct
    /// field bindings would otherwise let weight/reps edits change the last
    /// weighted set without clearing a now-stale rating.
    private func reconciledSetBinding(
        entry: Binding<LogExerciseDraft>,
        index: Int
    ) -> Binding<SetDraft> {
        Binding(
            get: { entry.wrappedValue.sets[index] },
            set: {
                entry.wrappedValue.sets[index] = $0
                entry.wrappedValue.reconcileLastSetEffort()
            }
        )
    }

    @ViewBuilder
    private func setFields(set: Binding<SetDraft>, exercise: String, number: Int) -> some View {
        weightField(value: set.weight,
                    suggestion: suggestedWeight(for: exercise),
                    accessibilityLabel: "\(exercise), set \(number), weight")
        integerField("Reps", suffix: nil, value: set.reps,
                     accessibilityLabel: "\(exercise), set \(number), reps")
        integerField("Duration", suffix: "sec", value: set.seconds,
                     accessibilityLabel: "\(exercise), set \(number), duration in seconds")
    }

    private func weightField(
        value: Binding<Double?>,
        suggestion: String?,
        accessibilityLabel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldLabel("Weight")
            HStack(spacing: 4) {
                TextField(suggestion ?? "—", value: value, format: .number)
                    .keyboardType(.decimalPad)
                    .focused($isNumericFieldFocused)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel(accessibilityLabel)
                    .accessibilityHint(suggestion.map { "Suggested value \($0)" } ?? "Optional")
                Text(defaultUnit.label).foregroundStyle(.secondary)
            }
            .scaledFont(16, weight: .semibold, relativeTo: .body)
            .frame(maxWidth: .infinity, minHeight: fieldMinHeight)
            .padding(.horizontal, 10)
            .cardSurface(radius: AppRadius.card)
        }
    }

    private func integerField(
        _ title: String,
        suffix: String?,
        value: Binding<Int?>,
        suggestion: String? = nil,
        accessibilityLabel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldLabel(title)
            HStack(spacing: 4) {
                TextField(suggestion ?? "—", value: value, format: .number)
                    .keyboardType(.numberPad)
                    .focused($isNumericFieldFocused)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel(accessibilityLabel)
                    .accessibilityHint(suggestion.map { "Suggested value \($0)" } ?? "Optional")
                if let suffix { Text(suffix).foregroundStyle(.secondary) }
            }
            .scaledFont(16, weight: .semibold, relativeTo: .body)
            .frame(maxWidth: .infinity, minHeight: fieldMinHeight)
            .padding(.horizontal, 10)
            .cardSurface(radius: AppRadius.card)
        }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .scaledFont(12, weight: .semibold, relativeTo: .caption)
            .foregroundStyle(.secondary)
    }

    private func effortBinding(for entry: Binding<LogExerciseDraft>) -> Binding<Int?> {
        return Binding(
            get: { entry.wrappedValue.lastSetRepsInReserve },
            set: { entry.wrappedValue.setLastSetRepsInReserve($0) }
        )
    }

    private func suggestedWeight(for exercise: String) -> String? {
        guard let slug = entries.first(where: { $0.trimmedLabel == exercise })?.moveSlug,
              let weight = dumbbellDefaults.weight(forMoveSlug: slug) else { return nil }
        return formatted(weight)
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
            activeCalories = log.activeEnergyKcal.map { Int($0.rounded()) }
            note = log.note ?? ""
        }
        entries = draftEntries()
        initialEntries = entries
        initialPerformedAt = performedAt
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
                                        sets: [.empty]))
    }

    private func deleteExercise(id: LogExerciseDraft.ID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries.remove(at: index)
    }

    private func requestExerciseDeletion(id: LogExerciseDraft.ID) {
        guard let entry = entries.first(where: { $0.id == id }) else { return }
        if entry.shouldPersist {
            pendingExerciseDeletion = id
        } else {
            deleteExercise(id: id)
        }
    }

    private func confirmExerciseDeletion() {
        guard let id = pendingExerciseDeletion else { return }
        pendingExerciseDeletion = nil
        deleteExercise(id: id)
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
        let log = editingLog ?? WorkoutLog(workoutId: workout?.id ?? "",
                                           performedAt: performedAt,
                                           note: note.isEmpty ? nil : note)
        if editingLog == nil { context.insert(log) }

        log.performedAt = performedAt
        log.activeEnergyKcal = (activeCalories ?? 0) > 0 ? Double(activeCalories!) : nil
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

    private func cancel() {
        if hasEnteredData {
            showingDiscardConfirmation = true
        } else {
            dismiss()
        }
    }

    private var hasEnteredData: Bool {
        if isEditing {
            return performedAt != initialPerformedAt
                || activeCalories != editingLog?.activeEnergyKcal.map { Int($0.rounded()) }
                || note != (editingLog?.note ?? "")
                || entries != initialEntries
        }
        return performedAt != initialPerformedAt || activeCalories != nil
            || !note.isEmpty || entries != initialEntries
    }

    private func isWeightedRepSet(_ set: SetDraft) -> Bool {
        (set.weight ?? 0) > 0 && (set.reps ?? 0) > 0
    }
}
