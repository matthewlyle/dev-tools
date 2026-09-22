import SwiftUI

struct RawResponseView<Header: View>: View {
    let document: ResponseDocument
    let response: PlexResponse
    @Binding var collapsed: Set<Int>
    @ViewBuilder let header: () -> Header

    @AppStorage("rawWrapLines") private var wrap = true

    var body: some View {
        if document.format == .image {
            FillingScrollView {
                header()
                ImageBody(response: response)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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

/// An image response shown as the image, never upscaled, with its pixel size.
private struct ImageBody: View {
    let response: PlexResponse

    @State private var image: PlatformImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                VStack(spacing: 8) {
                    Image(platformImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: image.size.width, maxHeight: image.size.height)
                        .clipShape(.rect(cornerRadius: 8))
                        .accessibilityLabel("Response image")
                    Text("\(Int(image.size.width)) × \(Int(image.size.height))")
                        .font(.code(.caption))
                        .foregroundStyle(.secondary)
                }
                .padding(16)
            } else if failed {
                ContentUnavailableView(
                    "Can't Show Image",
                    systemImage: "photo",
                    description: Text("The body is labelled \(response.contentType ?? "an image") but couldn't be decoded. Check the Headers tab.")
                )
            } else {
                ProgressView()
            }
        }
        .task(id: response.receivedAt) {
            image = PlatformImage(data: response.body)
            failed = image == nil
        }
    }
}

/// Copy for the body. Rides the response header row rather than a row of its own.
struct BodyControls: View {
    let document: ResponseDocument
    let response: PlexResponse

    /// Unwrapped text needs an infinite-width container, which defeats
    /// TextKit's viewport layout: the whole body is laid out on the main
    /// thread, in time proportional to its size. Wrapped, layout stays
    /// proportional to what's on screen, so big bodies are always wrapped.
    static let wrapForcedAbove = 256 * 1024

    static func wrapForced(for document: ResponseDocument) -> Bool {
        document.text.utf8.count > wrapForcedAbove
    }

    var body: some View {
        let isImage = document.format == .image
        Button {
            if isImage {
                if let image = PlatformImage(data: response.body) { Clipboard.copy(image) }
            } else {
                Clipboard.copy(document.text.isEmpty ? response.bodyText : document.text)
            }
        } label: {
            Label(isImage ? "Copy Image" : "Copy Body", systemImage: "doc.on.doc")
                .labelStyle(.iconOnly)
        }
        .help(isImage ? "Copy image" : "Copy body")
        .buttonStyle(.borderless)
    }
}
