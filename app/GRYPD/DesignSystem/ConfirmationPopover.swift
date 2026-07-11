import SwiftUI

/// A ChatGPT-style confirmation bubble that anchors to the control that triggered
/// it, instead of a full-width action sheet or centred alert detached from the
/// button the user just tapped.
///
/// On iPhone a plain `.popover` adapts into a sheet; `.presentationCompactAdaptation(.popover)`
/// keeps the anchored bubble — caret and all — in a compact width. Present it with
/// `.confirmationPopover(...)` (or a bare `.popover`) attached *directly* to the
/// triggering button so the caret points at it.
///
/// The bubble shows a bold title, a secondary explanatory line, and a single
/// action button; tapping outside cancels, matching the reference UI.
struct ConfirmationPopover: View {
    let title: String
    let message: String
    let confirmTitle: String
    var role: ButtonRole? = nil
    let confirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(role: role, action: confirm) {
                Text(confirmTitle)
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(role == .destructive ? .red : .brand)
        }
        .padding(16)
        .frame(width: 280)
        // The app is forced-dark; popover content presents in its own context, so
        // opt it back into dark to match every other surface.
        .preferredColorScheme(.dark)
        .presentationCompactAdaptation(.popover)
    }
}

extension View {
    /// Presents a `ConfirmationPopover` anchored to this view. Attach it to the
    /// button (or row) that arms the confirmation so the caret points at it.
    ///
    /// `isPresented` is set to `false` before `confirm` runs, so `confirm` must
    /// not depend on any state cleared by that binding's setter — capture what it
    /// needs directly (e.g. the row's `log`).
    func confirmationPopover(
        isPresented: Binding<Bool>,
        title: String,
        message: String,
        confirmTitle: String,
        role: ButtonRole? = nil,
        arrowEdge: Edge? = nil,
        confirm: @escaping () -> Void
    ) -> some View {
        popover(isPresented: isPresented, arrowEdge: arrowEdge) {
            ConfirmationPopover(
                title: title,
                message: message,
                confirmTitle: confirmTitle,
                role: role
            ) {
                isPresented.wrappedValue = false
                confirm()
            }
        }
    }
}
