import SwiftUI
import SwiftData

/// A searchable list of moves for the logging sheet's "Add Exercise" flow. Offers
/// both catalog moves (from `taxonomy.json`) and the user's own `CustomMove`s,
/// fully blended into one list. Selection is enforced (no free-form logging) so
/// every logged move carries a stable `moveSlug` — the key progression groups by.
///
/// When search finds nothing, the empty state offers "Create custom exercise",
/// which opens a naming dialog pre-filled with the query so creation is always
/// deliberate and the name is editable before it's committed. On confirm the name
/// is slugified with the pipeline's exact rule and resolved to an existing catalog
/// move, an existing custom move, or a new `CustomMove` — never a duplicate slug.
/// Custom rows carry a swipe-to-delete; catalog rows don't.
///
/// 100% native: a `List` in a `NavigationStack` with `.searchable`, styled onto
/// the app's black canvas with the shared card-surface row fill.
struct MovePickerView: View {
    let taxonomy: Taxonomy
    /// Move slugs already present in the session — hidden from the list.
    let excluded: Set<String>
    let onSelect: (_ slug: String, _ label: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \CustomMove.label) private var customMoves: [CustomMove]
    @State private var query = ""
    /// Drives the naming dialog; `draftName` is its editable, pre-filled field.
    @State private var isNaming = false
    @State private var draftName = ""

    /// One selectable row. `custom` is non-nil only for user-created moves, which
    /// gates the swipe-to-delete action.
    private struct MoveRow: Identifiable {
        let slug: String
        let label: String
        let custom: CustomMove?
        var id: String { slug }
    }

    private var allMoves: [MoveRow] {
        var bySlug: [String: MoveRow] = [:]
        for (slug, label) in taxonomy.moves {
            bySlug[slug] = MoveRow(slug: slug, label: label, custom: nil)
        }
        // Custom moves fill only slugs the catalog doesn't already own: catalog
        // wins so a not-yet-reconciled overlap never renders twice.
        for move in customMoves where bySlug[move.slug] == nil {
            bySlug[move.slug] = MoveRow(slug: move.slug, label: move.label, custom: move)
        }
        return bySlug.values
            .filter { !excluded.contains($0.slug) }
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    private var results: [MoveRow] {
        guard !trimmedQuery.isEmpty else { return allMoves }
        return allMoves.filter { $0.label.localizedCaseInsensitiveContains(trimmedQuery) }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Offer creation once the query is narrow enough that the wanted move
    /// clearly isn't in the catalog — i.e. it's actively searching and only a
    /// handful (or zero) moves still match. Keeps the button out of the way while
    /// browsing the full list.
    private var showCreateButton: Bool {
        !trimmedQuery.isEmpty && results.count <= 5
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
            .alert("New Exercise", isPresented: $isNaming) {
                TextField("Exercise name", text: $draftName)
                    .textInputAutocapitalization(.words)
                Button("Cancel", role: .cancel) { }
                Button("Create") { commitCreate() }
            } message: {
                Text("Add your own exercise to log and track it.")
            }
        }
        .preferredColorScheme(.dark)
        .sheetPresentation()
        .presentationBackground(.black)
    }

    @ViewBuilder private var content: some View {
        VStack(spacing: 0) {
            if results.isEmpty {
                emptyState
            } else {
                movesList
            }
            if showCreateButton {
                createButton
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
            }
        }
    }

    private var createButton: some View {
        Button { startNaming() } label: {
            Label("Create Exercise", systemImage: "plus.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .tint(.brand)
        .foregroundStyle(Color.onBrand)
        .scaledFont(15, weight: .semibold, relativeTo: .subheadline)
    }

    private var movesList: some View {
        List {
            ForEach(results) { move in
                Button {
                    finish(slug: move.slug, label: move.label)
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
                .swipeActions(edge: .trailing) {
                    if let custom = move.custom {
                        Button(role: .destructive) { delete(custom) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder private var emptyState: some View {
        if trimmedQuery.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            // The create button sits just below; keep the body a quiet caption.
            ContentUnavailableView("No matching exercise", systemImage: "magnifyingglass",
                                   description: Text("Create “\(trimmedQuery)” below to log and track it."))
        }
    }

    /// Open the naming dialog, pre-filled with the current query so the user can
    /// correct a partial or mistyped search before anything is written.
    private func startNaming() {
        draftName = trimmedQuery
        isNaming = true
    }

    /// Commit the dialog: resolve the confirmed name to a stable slug without ever
    /// forking identity — prefer an existing catalog move, then an existing custom
    /// move, else create a new one. Selection is by slug, so a later catalog move
    /// of the same slug merges automatically. A blank/punctuation-only name yields
    /// an empty slug and is silently ignored.
    private func commitCreate() {
        let label = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        let slug = CustomMove.slug(from: label)
        guard !slug.isEmpty else { return }

        if let catalogLabel = taxonomy.moves[slug] {
            finish(slug: slug, label: catalogLabel)
        } else if let existing = customMoves.first(where: { $0.slug == slug }) {
            finish(slug: slug, label: existing.label)
        } else {
            let move = CustomMove(slug: slug, label: label)
            context.insert(move)
            try? context.save()
            finish(slug: slug, label: label)
        }
    }

    /// Deletes only the `CustomMove` record; logged history keeps its own slug +
    /// label copy, so past sessions and progression are untouched.
    private func delete(_ move: CustomMove) {
        context.delete(move)
        try? context.save()
    }

    private func finish(slug: String, label: String) {
        onSelect(slug, label)
        dismiss()
    }
}
