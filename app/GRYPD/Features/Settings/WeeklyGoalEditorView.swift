import SwiftUI
import SwiftData

/// A native editor for the immutable weekly-goal revisions used by the report engine.
/// Keeping the draft local means changing a Stepper never changes the goal until Save.
struct WeeklyGoalEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \WeeklyGoalRevision.effectiveFrom, order: .forward)
    private var revisions: [WeeklyGoalRevision]

    @State private var mode: WeeklyGoalMode
    @State private var totalTarget: Int
    @State private var upperTarget: Int
    @State private var lowerTarget: Int
    @State private var totalBodyTarget: Int
    @State private var showingDisableConfirmation = false
    @State private var errorMessage: String?

    init(existing: WeeklyGoalDefinition? = nil) {
        let definition = existing
        _mode = State(initialValue: definition?.mode ?? .total)
        _totalTarget = State(initialValue: definition?.totalTarget ?? 1)
        _upperTarget = State(initialValue: definition?.upperTarget ?? 0)
        _lowerTarget = State(initialValue: definition?.lowerTarget ?? 0)
        _totalBodyTarget = State(initialValue: definition?.totalBodyTarget ?? 0)
    }

    var body: some View {
        Form {
            goalTypeSection
            targetSection
            disableSection
        }
        .navigationTitle("Weekly Goal")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                // Save applies immediately and returns to Settings — no mid-save
                // confirmation, so the behaviour is the same on every edit. The
                // only confirmation left is the destructive Turn Off below.
                Button("Save", action: saveGoal)
                    .disabled(!canSave)
            }
        }
        .alert("Couldn’t save weekly goal", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private var goalTypeSection: some View {
        Section {
            Picker("Goal type", selection: $mode) {
                Text("Total").tag(WeeklyGoalMode.total)
                Text("By Body Focus").tag(WeeklyGoalMode.granular)
            }
            .pickerStyle(.inline)
        } header: {
            Text("Weekly Goal")
        } footer: {
            Text("Choose one way to define the number of workouts you want each week.")
        }
    }

    @ViewBuilder
    private var targetSection: some View {
        if mode == .total {
            Section("Total") {
                Stepper(value: $totalTarget, in: 1...14) {
                    LabeledContent("Workouts per week", value: "\(totalTarget)")
                }
            }
        } else {
            Section {
                goalStepper("Upper Body", value: $upperTarget)
                goalStepper("Lower Body", value: $lowerTarget)
                goalStepper("Total Body", value: $totalBodyTarget)
            } header: {
                Text("By Body Focus")
            } footer: {
                Text("Set at least one body-focus target. Each target can be from 0 to 14 workouts.")
            }
        }
    }

    @ViewBuilder
    private var disableSection: some View {
        if hasActiveGoal {
            Section {
                Button("Turn Off Weekly Goal", role: .destructive) {
                    showingDisableConfirmation = true
                }
                .confirmationPopover(
                    isPresented: $showingDisableConfirmation,
                    title: "Turn off weekly goal?",
                    message: "Weekly tracking stops, your active run ends, and your best streak is preserved.",
                    confirmTitle: "Turn Off",
                    role: .destructive,
                    // Anchor below the row (arrow on its bottom edge) so the bubble
                    // opens into the empty space under the button instead of
                    // overlapping the goal cards above it.
                    arrowEdge: .bottom
                ) {
                    disableGoal()
                }
            }
        }
    }

    private var hasActiveGoal: Bool {
        revisions.last?.definition != nil
    }

    private var canSave: Bool {
        mode == .total || upperTarget + lowerTarget + totalBodyTarget > 0
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    @ViewBuilder
    private func goalStepper(_ title: String, value: Binding<Int>) -> some View {
        Stepper(value: value, in: 0...14) {
            LabeledContent(title, value: "\(value.wrappedValue)")
        }
    }

    private func makeDefinition() -> WeeklyGoalDefinition? {
        switch mode {
        case .total:
            return try? WeeklyGoalDefinition(totalTarget: totalTarget)
        case .granular:
            return try? WeeklyGoalDefinition(upperTarget: upperTarget,
                                              lowerTarget: lowerTarget,
                                              totalBodyTarget: totalBodyTarget)
        }
    }

    private func saveGoal() {
        guard let definition = makeDefinition() else {
            errorMessage = "The selected target is invalid."
            return
        }
        do {
            let revision = try WeeklyGoalRevision(definition: definition, effectiveFrom: .now)
            context.insert(revision)
            try context.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func disableGoal() {
        do {
            context.insert(WeeklyGoalRevision(disabled: .now))
            try context.save()
            // Let the anchored popover finish dismissing before the navigation
            // pop, otherwise it can flash back in on the Settings screen.
            DispatchQueue.main.async { dismiss() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension WeeklyGoalDefinition {
    var summary: String {
        switch mode {
        case .total:
            return "\(totalTarget ?? 0) workouts per week"
        case .granular:
            return enabledTargets
                .sorted { $0.key.rawValue < $1.key.rawValue }
                .map { "\($0.value) \($0.key.settingsLabel)" }
                .joined(separator: ", ")
        }
    }
}

extension WorkoutBodyFocus {
    var settingsLabel: String {
        switch self {
        case .upperBody: return "upper"
        case .lowerBody: return "lower"
        case .totalBody: return "total body"
        }
    }
}
