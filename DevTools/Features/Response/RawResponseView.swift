import SwiftUI

struct RawResponseView<Header: View>: View {
    let document: ResponseDocument
    let response: PlexResponse
    @Binding var collapsed: Set<Int>
    @ViewBuilder let header: () -> Header

    @AppStorage("rawWrapLines") private var wrap = true

    var body: some View {
        if document.format == .image {
            VStack(spacing: 0) {
                header()
                ContentUnavailableView(
                    "Binary Image Body",
                    systemImage: "photo",
                    description: Text("\(response.byteCount.formatted(.byteCount(style: .file))) — see the Pretty tab.")
                )
            }
        } else {
            CodeTextView(
                text: document.text,
                tokens: document.tokens,
                folds: document.folds,
                collapsed: $collapsed,
                wrap: wrap || BodyControls.wrapForced(for: document),
                version: response.receivedAt,
                header: AnyView(header())
            )
        }
    }
}

/// Fold, wrap, and copy for the body. Rides the response header row rather
/// than a row of its own.
struct BodyControls: View {
    let document: ResponseDocument
    let response: PlexResponse
    @Binding var collapsed: Set<Int>

    @AppStorage("rawWrapLines") private var wrap = true

    /// Unwrapped text needs an infinite-width container, which defeats
    /// TextKit's viewport layout: the whole body is laid out on the main
    /// thread, in time proportional to its size. Wrapped, layout stays
    /// proportional to what's on screen, so big bodies are always wrapped.
    static let wrapForcedAbove = 256 * 1024

    static func wrapForced(for document: ResponseDocument) -> Bool {
        document.text.utf8.count > wrapForcedAbove
    }

    private var wrapForced: Bool { Self.wrapForced(for: document) }

    var body: some View {
        HStack(spacing: 12) {
            if !document.folds.isEmpty {
                Button {
                    collapsed = Set(document.folds.filter { $0.depth >= 1 }.map(\.id))
                } label: {
                    Label("Collapse All", systemImage: "arrow.down.right.and.arrow.up.left")
                        .labelStyle(.iconOnly)
                }
                .help("Collapse all")
                Button {
                    collapsed = []
                } label: {
                    Label("Expand All", systemImage: "arrow.up.left.and.arrow.down.right")
                        .labelStyle(.iconOnly)
                }
                .help("Expand all")
                .disabled(collapsed.isEmpty)
            }
            Toggle("Wrap", isOn: Binding(
                get: { wrap || wrapForced },
                set: { wrap = $0 }
            ))
                .platformCheckboxToggleStyle()
                .controlSize(.small)
                .disabled(wrapForced)
                .help(wrapForced ? "Bodies over \(BodyControls.wrapForcedAbove.formatted(.byteCount(style: .file))) are always wrapped; unwrapped layout would stall." : "Wrap long lines")
            Button {
                Clipboard.copy(document.text.isEmpty ? response.bodyText : document.text)
            } label: {
                Label("Copy Body", systemImage: "doc.on.doc")
                    .labelStyle(.iconOnly)
            }
            .help("Copy body")
        }
        .buttonStyle(.borderless)
    }
}
