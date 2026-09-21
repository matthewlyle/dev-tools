import SwiftUI

struct RawResponseView: View {
    let document: ResponseDocument
    let response: PlexResponse

    @AppStorage("rawWrapLines") private var wrap = false
    @State private var collapsed: Set<Int> = []

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
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                    }
                    .help("Collapse all")
                    Button {
                        collapsed = []
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .help("Expand all")
                    .disabled(collapsed.isEmpty)
                }
                Toggle("Wrap", isOn: $wrap)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(document.text.isEmpty ? response.bodyText : document.text, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
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
                    wrap: wrap,
                    version: response.receivedAt
                )
            }
        }
        .onChange(of: response.receivedAt) { _, _ in
            collapsed = []
        }
    }
}
