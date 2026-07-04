import SwiftUI  // 100% native — no UIKit or third-party dependencies.

/// Shared surface + layout primitives — the single source of truth for the app's
/// "dark, carded, generative-hero" look. Every screen composes these instead of
/// re-deriving spacing, radii, card fills, section headers, or the detail hero by
/// hand, so the UI is provably consistent (see the HARD REQUIREMENT in AGENTS.md)
/// and can't drift screen-to-screen.

// MARK: - Tokens

/// Corner radii. Three intentional tiers so a "row card" never accidentally uses
/// a "feature panel" radius, and vice-versa.
enum AppRadius {
    /// Small thumbnails (browse/history row artwork, session-card glyphs).
    static let thumbnail: CGFloat = 12
    /// List rows, tiles, weight cards, session cards.
    static let card: CGFloat = 18
    /// Larger content panels (charts, progress cards).
    static let panel: CGFloat = 22
    /// Hero-weight feature panels (the Progress overview / exercise hero).
    static let feature: CGFloat = 26
    /// Glass summary headers (History top stats).
    static let glass: CGFloat = 28
}

/// Vertical rhythm shared by the stacked detail screens.
enum AppSpacing {
    /// Gap between the full-bleed hero and the first content section.
    static let heroToContent: CGFloat = 24
    /// Gap between stacked content sections.
    static let section: CGFloat = 24
    /// Bottom padding under the last section in a scroll view.
    static let scrollBottom: CGFloat = 40
}

// MARK: - Sheet presentation

extension View {
    /// The app's one bottom-sheet presentation: a near-full-height detent (0.95)
    /// with `.large` as the fallback, plus a visible drag indicator. Applied to
    /// every sheet so they all share one height and the same grabber treatment —
    /// no sheet is allowed to define its own detents inline and drift.
    func sheetPresentation() -> some View {
        presentationDetents([.large])
            .presentationDragIndicator(.visible)
    }
}

// MARK: - Primary action button

/// The one set of metrics every primary call-to-action button uses (Let's Go /
/// Log Workout / View Workout / Add Exercise). Applying this to a Button's or
/// NavigationLink's label guarantees every CTA of this kind shares one height and
/// label font, so no two buttons can drift apart by-eye. Pair it with a native
/// button style (`.borderedProminent` for the primary tint, `.bordered` for the
/// secondary white) plus `.buttonBorderShape(.capsule)` — never a bespoke shape.
private struct PrimaryActionLabel: ViewModifier {
    // Grows with Dynamic Type so the button never clips at larger text sizes.
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 36

    func body(content: Content) -> some View {
        content
            .scaledFont(19, weight: .semibold, relativeTo: .body)
            .frame(maxWidth: .infinity)
            .frame(height: height)
    }
}

extension View {
    /// Standard primary-CTA label metrics — one uniform height and label font for
    /// every full-width action button in the app. Apply to the button's label, then
    /// keep the native `.buttonStyle(...)` + `.buttonBorderShape(.capsule)`.
    func primaryActionLabel() -> some View {
        modifier(PrimaryActionLabel())
    }
}

// MARK: - Card surface

/// The app's standard card surface: a faint white fill + hairline white stroke on
/// the black canvas. Centralizing it means the fill/stroke/radius are defined once.
private struct CardSurface: ViewModifier {
    var radius: CGFloat = AppRadius.card
    var fillOpacity: Double = 0.06
    var strokeOpacity: Double = 0.07

    func body(content: Content) -> some View {
        content
            .background(Color.white.opacity(fillOpacity), in: .rect(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.white.opacity(strokeOpacity), lineWidth: 1)
            )
    }
}

extension View {
    /// Apply the standard card surface (faint fill + hairline stroke). Override the
    /// radius with an `AppRadius` token; the fill/stroke default to the app standard.
    func cardSurface(radius: CGFloat = AppRadius.card,
                     fillOpacity: Double = 0.06,
                     strokeOpacity: Double = 0.07) -> some View {
        modifier(CardSurface(radius: radius, fillOpacity: fillOpacity, strokeOpacity: strokeOpacity))
    }

    /// A brand-tinted feature panel: the card surface with a lime gradient wash in
    /// the top-leading corner. Used for the "hero" summary panels on Progress.
    func featurePanel(radius: CGFloat = AppRadius.feature) -> some View {
        self
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay {
                        LinearGradient(colors: [Color.brand.opacity(0.18), .clear],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                            .clipShape(.rect(cornerRadius: radius))
                    }
            }
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

// MARK: - Section header

/// Optional accessory shown after a section title.
enum SectionAccessory {
    /// A count rendered in brand lime (e.g. "Exercise Progression  12").
    case count(Int)
    /// Muted supporting text (e.g. "3 moves").
    case text(String)
}

/// The one section header used across every screen: bold white title with an
/// optional trailing accessory. Replaces the three hand-rolled variants that used
/// to live in WorkoutDetail, LogDetail, and Progression.
struct SectionHeader: View {
    let title: String
    var accessory: SectionAccessory?

    init(_ title: String, accessory: SectionAccessory? = nil) {
        self.title = title
        self.accessory = accessory
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(title)
                .sectionHeaderFont()
                .foregroundStyle(.white)
            switch accessory {
            case .count(let n):
                Text("\(n)")
                    .scaledFont(15, weight: .bold, relativeTo: .subheadline)
                    .foregroundStyle(Color.brand)
            case .text(let s):
                Text(s)
                    .scaledFont(15, weight: .medium, relativeTo: .subheadline)
                    .foregroundStyle(.white.opacity(0.4))
            case nil:
                EmptyView()
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Month section header (accordion)

/// Tappable section header that toggles its month open/closed, shared by the
/// Browse and History screens so a month reads as the same "kind" of group in
/// both places. The chevron rotates to point down when expanded, right when
/// collapsed. The trailing count is brand lime, matching `SectionHeader`.
struct MonthSectionHeader: View {
    let label: String
    let count: Int
    let isCollapsed: Bool
    let toggle: () -> Void
    /// Noun used in the VoiceOver label ("workouts" vs "sessions").
    var noun: String = "sessions"

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                Text(label)
                    .sectionHeaderFont()
                    .foregroundStyle(.white)
                Text("\(count)")
                    .scaledFont(15, weight: .bold, relativeTo: .subheadline)
                    .foregroundStyle(Color.brand)
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label), \(count) \(noun)")
        .accessibilityHint(isCollapsed ? "Expand" : "Collapse")
        .accessibilityAddTraits(.isButton)
    }
}


/// The full-bleed generative hero shared by the two detail screens. A fixed-size
/// backdrop (never resizes, nothing loads async) is darkened into the black
/// canvas; the caller pins a title block bottom-leading.
///
/// Passing a `workout` uses its generative `WorkoutHeroBackground`; passing `nil`
/// (a logged session whose workout left the catalog) falls back to a neutral slate.
///
/// The back / + / menu controls are **not** rendered here. They are native nav-bar
/// toolbar items (system back chevron leading, `controls` trailing) supplied by
/// `HeroDetailLayout`, so they stay pinned while the hero and content scroll —
/// matching the native iOS pattern where the nav bar's toolbar items never scroll.
struct DetailHero<Title: View>: View {
    let workout: Workout?
    @ViewBuilder var title: () -> Title

    // Grows with Dynamic Type so the hero never clips at larger text sizes.
    @ScaledMetric(relativeTo: .largeTitle) private var height: CGFloat = 310

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            backdrop
                .frame(height: height)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay {
                    LinearGradient(colors: [.clear, .clear, .black.opacity(0.6), .black],
                                   startPoint: .top, endPoint: .bottom)
                }

            title()
                .padding(.horizontal, 20)
                .padding(.bottom, 6)
        }
    }

    @ViewBuilder private var backdrop: some View {
        if let workout {
            // Fixed container owns the layout; the generative artwork is a clipped
            // overlay so the hero can never resize.
            Color(white: 0.12).overlay { WorkoutHeroBackground(workout: workout) }
        } else {
            ZStack {
                LinearGradient(colors: [Color(hex: 0x2E2E44), Color(hex: 0x141422)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "questionmark.circle")
                    .resizable().scaledToFit()
                    .frame(width: 96, height: 96)
                    .foregroundStyle(.white.opacity(0.16))
                    .padding(.bottom, 40)
            }
        }
    }
}

/// The scaffold every hero-detail screen (workout + logged session) is built on:
/// black canvas, full-bleed hero, and a scroll container with the shared hero →
/// content rhythm. Callers supply the hero, the trailing nav-bar controls
/// (+ / ellipsis-menu), and the stacked content sections; this guarantees both
/// screens share one skeleton.
///
/// The navigation bar is kept in the hierarchy but made fully transparent
/// (`.toolbarBackground(.hidden, for: .navigationBar)`) so the hero bleeds under
/// the status bar — the same pattern Apple's own full-bleed detail screens use
/// (e.g. Photos). Because the bar stays present, Apple's native back chevron
/// (leading) and the interactive edge-swipe-to-pop gesture both work unchanged;
/// the caller's `controls` are placed as `.topBarTrailing` toolbar items, which
/// Apple pins to the nav bar so they never scroll away.
struct HeroDetailLayout<Hero: View, Controls: View, Content: View>: View {
    @ViewBuilder var hero: () -> Hero
    @ViewBuilder var controls: () -> Controls
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.heroToContent) {
                hero()
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    content()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, AppSpacing.scrollBottom)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(Color.black.ignoresSafeArea())
        // Transparent bar over a full-bleed hero; system back chevron (leading)
        // + edge-swipe-to-pop stay native, caller controls pin to topBarTrailing.
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) { controls() }
        }
    }
}
