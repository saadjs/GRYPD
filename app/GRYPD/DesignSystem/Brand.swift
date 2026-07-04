import SwiftUI

/// Brand design tokens — LOCKED design decision.
///
/// The app's accent is the Apple Fitness+ lime green, a single fixed value used
/// in both light and dark mode. It lives in the `AccentColor` asset, so the whole
/// app tints off it automatically via `Color.accentColor`:
///   • #B5FF29 (sRGB 0.710, 1.000, 0.161) — the lime green used everywhere.
///
/// Rule: the green is used as a *fill* (buttons, selected chips, tab) always
/// paired with near-black text (`onBrand`) — never white. Neon-on-white is
/// illegible/off-brand; Fitness+ itself pairs the green with black.
extension Color {
    /// The single source of truth for the accent, read from the asset catalog.
    static let brand = Color.accentColor

    /// Foreground to place on top of a `brand`-filled surface. Black reads on
    /// the lime green in both light and dark mode.
    static let onBrand = Color.black

    /// The lime green, hard-coded for cases that can't read the asset
    /// (e.g. gradients). Keep in sync with `AccentColor.colorset`.
    static let brandHex = Color(.sRGB, red: 0.710, green: 1.000, blue: 0.161)
}