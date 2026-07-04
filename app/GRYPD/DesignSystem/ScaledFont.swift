import SwiftUI

/// A system font of an *exact* point size that still scales with Dynamic Type.
///
/// `Font.system(size:)` is frozen — it ignores the user's text-size setting. This
/// modifier keeps the hand-tuned size (so the UI is pixel-accurate at the default
/// setting) while scaling it relative to a chosen text style, so the whole app
/// honors Dynamic Type end-to-end.
///
///     Text("Filter").scaledFont(20, weight: .bold, relativeTo: .title3)
private struct ScaledFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design

    init(_ size: CGFloat, weight: Font.Weight, design: Font.Design, relativeTo style: Font.TextStyle) {
        self._size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}

extension View {
    /// System font at `size` pt (exact at the default text size) that scales with
    /// Dynamic Type along `style`'s curve.
    func scaledFont(_ size: CGFloat,
                    weight: Font.Weight = .regular,
                    design: Font.Design = .default,
                    relativeTo style: Font.TextStyle = .body) -> some View {
        modifier(ScaledFont(size, weight: weight, design: design, relativeTo: style))
    }

    // MARK: Shared type scale
    //
    // One source of truth so the same role is the same size on every screen
    // (Filter, Detail, …) and can't drift apart.

    /// Section headers ("Time", "Muscle Groups", "Moves", "Your History", …).
    func sectionHeaderFont() -> some View { scaledFont(20, weight: .bold, relativeTo: .title3) }

    /// The workout/session title overlaid on a detail hero. One size across both
    /// detail screens so they read as the same kind of page.
    func heroTitleFont() -> some View { scaledFont(34, weight: .bold, relativeTo: .largeTitle) }

    /// Primary body/label text (facet chips, meta lines, moves, descriptions).
    func primaryLabelFont(weight: Font.Weight = .regular) -> some View {
        scaledFont(17, weight: weight, relativeTo: .body)
    }
}
