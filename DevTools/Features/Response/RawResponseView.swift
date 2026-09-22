import SwiftUI

struct RawResponseView: View {
    let document: ResponseDocument
    let response: PlexResponse

    @AppStorage("rawWrapLines") private var wrap = true
    @State private var collapsed: Set<Int> = []

    /// Unwrapped text needs an infinite-width container, which defeats
    /// TextKit's viewport layout: the whole body is laid out on the main
    /// thread, in time proportional to its size. Wrapped, layout stays
    /// proportional to what's on screen, so big bodies are always wrapped.
    static let wrapForcedAbove = 256 * 1024

    private var wrapForced: Bool { document.text.utf8.count > Self.wrapForcedAbove }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(document.format.label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                if let notice = document.notice {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
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
                    .help(wrapForced ? "Bodies over \(Self.wrapForcedAbove.formatted(.byteCount(style: .file))) are always wrapped; unwrapped layout would stall." : "Wrap long lines")
                Button {
                    Clipboard.copy(document.text.isEmpty ? response.bodyText : document.text)
                } label: {
                    Label("Copy Body", systemImage: "doc.on.doc")
                        .labelStyle(.iconOnly)
                }
                .help("Copy body")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            if document.format == .image {
                ContentUnavailableView(
                    "Binary Image Body",
                    systemImage: "photo",
                    description: Text("\(response.byteCount.formatted(.byteCount(style: .file))) — see the Pretty tab.")
                )
            } else {
                CodeTextView(
                    text: document.text,
                    tokens: document.tokens,
                    folds: document.folds,
                    collapsed: $collapsed,
                    wrap: wrap || wrapForced,
                    version: response.receivedAt
                )
            }
        }
        .onChange(of: response.receivedAt) { _, _ in
            collapsed = []
        }
    }
}
