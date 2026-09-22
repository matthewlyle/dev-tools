import SwiftUI

/// A short-input sheet's frame. The Mac's is a fixed-width panel with the
/// title on top and the buttons trailing along the bottom. iOS puts the
/// title, Cancel, and the confirming action in a navigation bar over content
/// that fills the sheet: an iPhone sheet is the screen's width, so a fixed
/// width clips, and the HIG puts a sheet's actions in its bar there.
struct SheetScaffold<Subtitle: View, Content: View>: View {
    let title: String
    let width: CGFloat
    let confirm: SheetAction
    var secondary: SheetAction? = nil
    var busy = false
    @ViewBuilder let subtitle: () -> Subtitle
    @ViewBuilder let content: () -> Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                subtitle()
            }
            content()
            HStack {
                if busy {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                cancelButton
                if let secondary {
                    button(for: secondary)
                }
                button(for: confirm)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: width)
        #else
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    subtitle()
                    Spacer(minLength: 0)
                    if busy {
                        ProgressView().controlSize(.small)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                content()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { cancelButton }
                ToolbarItem(placement: .confirmationAction) {
                    button(for: confirm)
                        .keyboardShortcut(.defaultAction)
                }
                if let secondary {
                    ToolbarItem(placement: .bottomBar) { button(for: secondary) }
                }
            }
        }
        #endif
    }

    private var cancelButton: some View {
        Button("Cancel", role: .cancel) { dismiss() }
            .keyboardShortcut(.cancelAction)
    }

    private func button(for action: SheetAction) -> some View {
        Button(action.title) {
            action.run()
            dismiss()
        }
        .disabled(action.disabled)
    }
}

struct SheetAction {
    let title: String
    var disabled = false
    let run: () -> Void
}
