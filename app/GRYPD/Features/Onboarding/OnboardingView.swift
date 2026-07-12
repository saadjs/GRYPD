import SwiftUI  // 100% native — no UIKit or third-party dependencies.
import SwiftData

/// First-run onboarding flow, gated by the `hasCompletedOnboarding` AppStorage
/// flag that `RootTabView` uses to present it as a `.fullScreenCover`.
struct OnboardingView: View {
    // Set to true when the user finishes or skips; the cover is bound to its
    // inverse in RootTabView, so dismissing here is what ends the flow.
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WeeklyGoalRevision.effectiveFrom, order: .reverse)
    private var weeklyGoalRevisions: [WeeklyGoalRevision]
    @State private var page = 0
    @State private var saveError: String?

    private static let pages: [OnboardingPage] = [
        OnboardingPage(
            symbol: "figure.strengthtraining.traditional",
            title: "Welcome to GRYPD",
            // "GRYPD" reads as "gripped"; Fitness+ Strength is dumbbells only.
            gloss: "gripped  ·  /ɡrɪpt/  ·  a dumbbell in each hand",
            body: "Apple Fitness+ Strength is all dumbbells. GRYPD is your companion for it: grab the right pair, log every lift, and get properly gripped."
        ),
        OnboardingPage(
            symbol: "line.3.horizontal.decrease.circle",
            title: "Find the right workout",
            body: "Filter Fitness+ Strength workouts by muscle group, duration, body focus, and equipment, then open the episode in Fitness+ to play it."
        ),
        OnboardingPage(
            symbol: "square.and.pencil",
            title: "Log every lift",
            body: "Record the weight you lift per workout and per move. Set your light, medium, and heavy dumbbells once and GRYPD auto-fills the rest."
        ),
        OnboardingPage(
            symbol: "chart.line.uptrend.xyaxis",
            title: "Watch yourself get stronger",
            body: "Progression charts per workout and per move turn every logged session into a picture of your strength over time. Everything stays on your device, with no account, no analytics, and no sync."
        )
    ]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            TabView(selection: $page) {
                ForEach(Array(Self.pages.enumerated()), id: \.offset) { index, model in
                    OnboardingPageView(
                        page: model,
                        showsDocLinks: index == Self.pages.count - 1,
                        onContinue: advance
                    )
                    .tag(index)
                }
                WeeklyGoalOnboardingPage(existing: weeklyGoalRevisions.first?.definition,
                                         onSave: saveGoal,
                                         onNotNow: finish)
                    .tag(Self.pages.count)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button("Skip", action: skip)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.top, 8)
                .padding(.trailing, 20)
        }
        // Force dark regardless of the system setting.
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
        .alert("Unable to save goal", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "Please try again.")
        }
    }

    private func advance() {
        withAnimation { page = min(page + 1, Self.pages.count) }
    }

    private func saveGoal(_ definition: WeeklyGoalDefinition) {
        do {
            modelContext.insert(try WeeklyGoalRevision(definition: definition, effectiveFrom: .now))
            try modelContext.save()
            finish()
        } catch {
            saveError = "Your weekly goal could not be saved. Please try again."
        }
    }

    private func skip() {
        finish()
    }

    private func finish() {
        hasCompletedOnboarding = true
    }
}

// MARK: - Page model

/// Content for one onboarding page.
private struct OnboardingPage {
    let symbol: String
    let title: String
    /// Optional dictionary-style gloss under the title; only the first page sets it.
    var gloss: String? = nil
    let body: String
}

// MARK: - Page view

/// Renders one informational onboarding page: glyph, title, optional gloss,
/// body, and CTA (plus the doc links on the final informational page).
private struct OnboardingPageView: View {
    let page: OnboardingPage
    let showsDocLinks: Bool
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            // Content scrolls so it never clips at large Dynamic Type sizes.
            ScrollView {
                VStack(spacing: 20) {
                    // scaledFont sizes the SF Symbol and keeps it scaling with
                    // Dynamic Type (never Font.system(size:) — see CLAUDE.md).
                    Image(systemName: page.symbol)
                        .scaledFont(76, relativeTo: .largeTitle)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.brand)
                        .padding(.bottom, 4)
                        .accessibilityHidden(true)

                    Text(page.title)
                        .heroTitleFont()
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    // Phonetic gloss, pulled tight under the title.
                    if let gloss = page.gloss {
                        Text(gloss)
                            .scaledFont(15, weight: .semibold, relativeTo: .subheadline)
                            .italic()
                            .foregroundStyle(Color.brand)
                            .multilineTextAlignment(.center)
                            .padding(.top, -6)
                    }

                    Text(page.body)
                        .primaryLabelFont()
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)

                    if showsDocLinks {
                        docLinks
                            .padding(.top, 8)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 72)
                .padding(.horizontal, 28)
            }

            actionButton
                .padding(.horizontal, 28)
                // Leave room for the paging dots pinned at the very bottom.
                .padding(.bottom, 44)
        }
    }

    private var actionButton: some View {
        // Brand fill with onBrand (black) text, per the design-system CTA rule.
        Button(action: onContinue) {
            Text("Continue").primaryActionLabel()
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .tint(.brand)
        .foregroundStyle(Color.onBrand)
    }

    /// Doc links on grypd.saad.sh, opened in the browser via native `Link`.
    private var docLinks: some View {
        HStack(spacing: 20) {
            Link("Features", destination: URL(string: "https://grypd.saad.sh/features.html")!)
            Link("Privacy", destination: URL(string: "https://grypd.saad.sh/privacy.html")!)
            Link("Support", destination: URL(string: "https://grypd.saad.sh/support.html")!)
        }
        .scaledFont(15, weight: .semibold, relativeTo: .subheadline)
        .tint(Color.brand)
    }
}
