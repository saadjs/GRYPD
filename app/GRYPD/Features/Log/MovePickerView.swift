import SwiftUI

/// A searchable list of catalog moves for the logging sheet's "Add Exercise" flow.
/// Selection is enforced (no free-form text) so every logged move carries a stable
/// `moveSlug` — the key progression tracking groups by. Moves already in the session
/// are excluded so the list only offers what can still be added.
///
/// 100% native: a `List` in a `NavigationStack` with `.searchable`, styled onto the
/// app's black canvas with the shared card-surface row fill.
struct MovePickerView: View {
    let taxonomy: Taxonomy
    /// Move slugs already present in the session — hidden from the list.
    let excluded: Set<String>
    let onSelect: (_ slug: String, _ label: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var allMoves: [(slug: String, label: String)] {
        taxonomy.moves
            .map { (slug: $0.key, label: $0.value) }
            .filter { !excluded.contains($0.slug) }
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    private var results: [(slug: String, label: String)] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return allMoves }
        return allMoves.filter { $0.label.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                content
            }
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .searchable(text: $query, prompt: "Search exercises")
        }
        .preferredColorScheme(.dark)
        .sheetPresentation()
        .presentationBackground(.black)
    }

    @ViewBuilder private var content: some View {
        if results.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            List {
                ForEach(results, id: \.slug) { move in
                    Button {
                        onSelect(move.slug, move.label)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Text(move.label)
                                .primaryLabelFont(weight: .medium)
                                .foregroundStyle(.white)
                            Spacer(minLength: 12)
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(Color.brand)
                        }
                        .contentShape(.rect)
                    }
                    .listRowBackground(Color.white.opacity(0.06))
                    .listRowSeparatorTint(Color.white.opacity(0.08))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}
