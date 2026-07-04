import SwiftUI

/// Generative, 100%-native artwork for a workout — no bitmap assets and, by
/// design, no Apple Fitness+ imagery (which is Apple-copyrighted and not licensed
/// for third-party apps). Each workout gets a stable, "designed" identity:
///
///   • color  = trainer  → a trainer's episodes share a look (a mini brand)
///   • glyph  = body focus → you can read *what* it is at a glance
///
/// Everything renders on the app's black background and deliberately avoids the
/// lime brand green so `Color.brand` stays reserved as the accent (buttons,
/// trainer name). Glyphs are `resizable` images sized to their container, so no
/// frozen `Font.system(size:)` is used and Dynamic Type is never fought.
enum WorkoutArt {
    /// Curated deep, jewel-tone gradient pairs (top-leading → bottom-trailing).
    private static let palettes: [[Color]] = [
        [Color(hex: 0x1E3A5F), Color(hex: 0x0B1E36)],   // ocean
        [Color(hex: 0x3A1E5F), Color(hex: 0x1A0B36)],   // indigo
        [Color(hex: 0x0F4C4A), Color(hex: 0x07231F)],   // teal
        [Color(hex: 0x5F1E3A), Color(hex: 0x360B1E)],   // burgundy
        [Color(hex: 0x244A1E), Color(hex: 0x11230B)],   // forest
        [Color(hex: 0x5F3A1E), Color(hex: 0x36200B)],   // bronze
        [Color(hex: 0x2E2E44), Color(hex: 0x141422)],   // slate
        [Color(hex: 0x1E5F55), Color(hex: 0x0B362F)],   // deep emerald
    ]

    /// Deep gradient identity for a workout, keyed to its trainer.
    static func palette(for workout: Workout) -> [Color] {
        palettes[stableIndex(workout.trainer, mod: palettes.count)]
    }

    /// SF Symbol for the body region. One consistent family (all `figure.*`
    /// poses, so no lone piece of equipment sits next to people) with a distinct,
    /// region-appropriate stance for each:
    ///   • upper → arms open/raised (arms & shoulders)
    ///   • lower → a stepping figure (leg drive)
    ///   • total → a full-body functional lift
    /// All are available under the current deployment target.
    static func glyph(for workout: Workout) -> String {
        switch workout.facets.bodyFocus {
        case "upper-body": return "figure.arms.open"
        case "lower-body": return "figure.step.training"
        case "total-body": return "figure.strengthtraining.functional"
        default:           return "figure.strengthtraining.functional"
        }
    }

    /// Stable across launches (unlike `Hasher`, which is per-run seeded) so a
    /// trainer keeps the same color forever. Classic djb2.
    private static func stableIndex(_ s: String, mod: Int) -> Int {
        var h: UInt64 = 5381
        for b in s.utf8 { h = (h &* 33) &+ UInt64(b) }
        return Int(h % UInt64(mod))
    }
}

extension Color {
    /// Build a color from a 0xRRGGBB literal.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Body-focus glyph for the browse-list thumbnail. Just the monochrome SF Symbol
/// on the app background — no gradient tile — matching the History rows.
struct WorkoutTile: View {
    let workout: Workout
    var size: CGFloat = 60

    var body: some View {
        Image(systemName: WorkoutArt.glyph(for: workout))
            .resizable().scaledToFit()
            .frame(width: size * 0.5, height: size * 0.5)
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
    }
}

/// Full-bleed generative hero background for the detail screen: a layered
/// gradient with a light source and a large, faint body-focus watermark. The
/// caller overlays its own darkening scrim + title on top.
struct WorkoutHeroBackground: View {
    let workout: Workout

    var body: some View {
        ZStack {
            LinearGradient(colors: WorkoutArt.palette(for: workout),
                           startPoint: .topLeading, endPoint: .bottomTrailing)

            RadialGradient(colors: [.white.opacity(0.20), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 360)
        }
        // A modest, fully-visible glyph near the top — an intentional motif, not
        // a giant cropped shape. The title overlays the lower half from the caller.
        .overlay(alignment: .top) {
            Image(systemName: WorkoutArt.glyph(for: workout))
                .resizable().scaledToFit()
                .frame(width: 104, height: 104)
                .foregroundStyle(.white.opacity(0.18))
                .padding(.top, 104)
        }
    }
}
