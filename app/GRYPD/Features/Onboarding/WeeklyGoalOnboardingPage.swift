import SwiftUI

/// Final onboarding step. It owns only temporary form state; the shared goal
/// model remains the single source of truth for validation and persistence.
struct WeeklyGoalOnboardingPage: View {
    let onSave: (WeeklyGoalDefinition) -> Void
    let onNotNow: () -> Void

    @State private var mode: WeeklyGoalMode = .total
    @State private var totalTarget = 3
    @State private var upperTarget = 1
    @State private var lowerTarget = 1
    @State private var totalBodyTarget = 1

    var body: some View {
        VStack(spacing: 20) {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "target")
                        .scaledFont(76, relativeTo: .largeTitle)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.brand)
                        .accessibilityHidden(true)

                    Text("Set a weekly goal")
                        .heroTitleFont()
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text("Choose how you want to measure your workouts. You can change this later.")
                        .primaryLabelFont()
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)

                    Picker("Goal type", selection: $mode) {
                        Text("Total Weekly Workouts").tag(WeeklyGoalMode.total)
                        Text("By Body Focus").tag(WeeklyGoalMode.granular)
                    }
                    .pickerStyle(.menu)
                    .tint(Color.brand)
                    .cardSurface()

                    if mode == .total {
                        Stepper(value: $totalTarget, in: 1...14) {
                            goalValueLabel("Workouts per week", value: totalTarget)
                        }
                        .cardSurface()
                    } else {
                        VStack(spacing: 0) {
                            goalStepper("Upper Body", value: $upperTarget)
                            Divider().opacity(0.2)
                            goalStepper("Lower Body", value: $lowerTarget)
                            Divider().opacity(0.2)
                            goalStepper("Total Body", value: $totalBodyTarget)
                        }
                        .cardSurface()

                        Text("Set at least one body focus above zero.")
                            .scaledFont(15, relativeTo: .subheadline)
                            .foregroundStyle(.white.opacity(0.55))
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 72)
                .padding(.horizontal, 28)
                .padding(.bottom, 12)
            }

            VStack(spacing: 12) {
                Button(action: createGoal) {
                    Text("Set Goal").primaryActionLabel()
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(.brand)
                .foregroundStyle(Color.onBrand)

                Button(action: onNotNow) {
                    Text("Not Now").primaryActionLabel()
                }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(.white)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 44)
        }
    }

    private func createGoal() {
        do {
            switch mode {
            case .total:
                onSave(try WeeklyGoalDefinition(totalTarget: totalTarget))
            case .granular:
                onSave(try WeeklyGoalDefinition(upperTarget: upperTarget,
                                                lowerTarget: lowerTarget,
                                                totalBodyTarget: totalBodyTarget))
            }
        } catch {
            // The controls constrain values; this is a defensive guard for
            // future changes to the shared domain validation.
        }
    }

    private func goalStepper(_ title: String, value: Binding<Int>) -> some View {
        Stepper(value: value, in: 0...14) {
            goalValueLabel(title, value: value.wrappedValue)
        }
        .padding(.vertical, 12)
    }

    private func goalValueLabel(_ title: String, value: Int) -> some View {
        LabeledContent(title) {
            Text("\(value)")
                .primaryLabelFont(weight: .semibold)
                .foregroundStyle(Color.brand)
        }
    }
}
