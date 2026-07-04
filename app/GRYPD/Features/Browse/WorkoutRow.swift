import SwiftUI

/// One catalog workout as a **session card** — the same dark, generative-artwork
/// language as the History screen's rows, so a workout reads as the same "kind"
/// of thing whether you're browsing it here or looking back at a logged session
/// in History. The per-trainer gradient + body-focus glyph tile anchors the card;
/// the title headlines with trainer · duration · body-focus as supporting meta,
/// and a brand-lime "last done" line surfaces when the workout is in your history.
struct WorkoutRow: View {
    let workout: Workout
    let taxonomy: Taxonomy
    let lastDone: Date?

    /// Per-trainer gradient identity — identical mapping to the History cards.
    private var palette: [Color] { WorkoutArt.palette(for: workout) }

    /// Body-focus SF Symbol from the shared family, so a workout reads the same
    /// in Browse and History.
    private var glyph: String { WorkoutArt.glyph(for: workout) }

    private var metaLine: String {
        var parts: [String] = []
        if let ep = workout.episode { parts.append("Ep \(ep)") }
        parts.append(taxonomy.trainer(workout.trainer))
        parts.append(workout.durationLabel)
        parts.append(taxonomy.bodyFocus(workout.facets.bodyFocus))
        return parts.joined(separator: "  •  ")
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                LinearGradient(colors: palette,
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: glyph)
                    .resizable().scaledToFit()
                    .frame(width: 22, height: 22)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .frame(width: 44, height: 44)
            .clipShape(.rect(cornerRadius: AppRadius.thumbnail))

            VStack(alignment: .leading, spacing: 5) {
                Text(workout.title)
                    .scaledFont(16, weight: .semibold, relativeTo: .subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(metaLine)
                    .scaledFont(14, weight: .medium, relativeTo: .footnote)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                if let lastDone {
                    Label(lastDone.formatted(.relative(presentation: .named)),
                          systemImage: "checkmark.circle.fill")
                        .scaledFont(13, weight: .semibold, relativeTo: .caption)
                        .foregroundStyle(Color.brand)
                        .lineLimit(1)
                        .padding(.top, 1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .cardSurface()
    }
}
