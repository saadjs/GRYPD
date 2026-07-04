import SwiftUI  // 100% native — no UIKit or third-party dependencies.

/// First-run onboarding flow, gated by the `hasCompletedOnboarding` AppStorage
/// flag that `RootTabView` uses to present it as a `.fullScreenCover`.
struct OnboardingView: View {
    // Set to true when the user finishes or skips; the cover is bound to its
    // inverse in RootTabView, so dismissing here is what ends the flow.
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var page = 0

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

    private var isLastPage: Bool { page == Self.pages.count - 1 }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            TabView(selection: $page) {
                ForEach(Array(Self.pages.enumerated()), id: \.offset) { index, model in
                    OnboardingPageView(
                        page: model,
                        isLast: index == Self.pages.count - 1,
                        onContinue: advance,
                        onFinish: finish
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            // No Skip on the last page; its Get Started button finishes the flow.
            if !isLastPage {
                Button("Skip", action: finish)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 8)
                    .padding(.trailing, 20)
            }
        }
        // Force dark regardless of the system setting.
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
    }

    private func advance() {
        withAnimation { page = min(page + 1, Self.pages.count - 1) }
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

/// Renders one onboarding page: glyph, title, optional gloss, body, and CTA
/// (plus the doc links on the last page).
private struct OnboardingPageView: View {
    let page: OnboardingPage
    let isLast: Bool
    let onContinue: () -> Void
    let onFinish: () -> Void

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

                    if isLast {
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
        Button(action: isLast ? onFinish : onContinue) {
            Text(isLast ? "Get Started" : "Continue").primaryActionLabel()
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
