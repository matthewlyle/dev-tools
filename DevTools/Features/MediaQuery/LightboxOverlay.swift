import SwiftUI

struct LightboxOverlay: View {
    @Environment(LightboxStore.self) private var lightbox
    @Environment(ImageStore.self) private var images
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var expanded = false
    @State private var image: PlatformImage?

    private static let margin: CGFloat = 48
    private static let captionHeight: CGFloat = 64

    var body: some View {
        if let presentation = lightbox.presentation {
            GeometryReader { proxy in
                let bounds = proxy.frame(in: .global)
                let source = presentation.sourceFrame.offsetBy(dx: -bounds.minX, dy: -bounds.minY)
                let target = targetRect(in: proxy.size, aspect: aspect(fallback: source.size))
                let rect = expanded ? target : source

                ZStack(alignment: .topLeading) {
                    Color.black
                        .opacity(expanded ? 0.55 : 0)
                        .onTapGesture { close() }
                        .accessibilityHidden(true)

                    Group {
                        if let image {
                            Image(platformImage: image)
                                .resizable()
                                .scaledToFit()
                        } else {
                            Rectangle().fill(.quaternary)
                        }
                    }
                    .frame(width: rect.width, height: rect.height)
                    .clipShape(.rect(cornerRadius: expanded ? 12 : 8))
                    .shadow(color: .black.opacity(expanded ? 0.4 : 0), radius: 24, y: 8)
                    .position(x: rect.midX, y: rect.midY)
                    .accessibilityLabel(presentation.item.title)
                    .animation(reduceMotion ? nil : .smooth, value: expanded)

                    caption(for: presentation.item)
                        .frame(width: target.width)
                        .position(x: target.midX, y: target.maxY + Self.captionHeight / 2)
                        .opacity(expanded ? 1 : 0)
                }
                .animation(.smooth, value: expanded)
                .onAppear { expanded = true }
                .onDisappear { expanded = false; image = nil }
                .task(id: presentation.item.id) {
                    let server = presentation.server
                    let url = presentation.item.url
                    let preview = presentation.previewPixelSize
                    image = await images.image(for: url, server: server, width: Int(preview.width), height: Int(preview.height))
                    image = await images.image(for: url, server: server, width: 1920, height: 1280)
                }
            }
            .ignoresSafeArea()
        }
    }

    private func caption(for item: LightboxItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                Text(item.url)
                    .font(.code(.callout))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer()
            Button(action: close) {
                Label("Close", systemImage: "xmark.circle.fill")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.cancelAction)
            .help("Close (Esc)")
        }
        .padding(.horizontal, 4)
        .padding(.top, 12)
        .colorScheme(.dark)
    }

    private func aspect(fallback: CGSize) -> CGFloat {
        if let image, image.size.height > 0 { return image.size.width / image.size.height }
        return fallback.height > 0 ? fallback.width / fallback.height : 1.5
    }

    private func targetRect(in size: CGSize, aspect: CGFloat) -> CGRect {
        let available = CGSize(
            width: max(size.width - Self.margin * 2, 200),
            height: max(size.height - Self.margin * 2 - Self.captionHeight, 200)
        )
        var width = available.width
        var height = width / aspect
        if height > available.height {
            height = available.height
            width = height * aspect
        }
        return CGRect(
            x: (size.width - width) / 2,
            y: (size.height - Self.captionHeight - height) / 2,
            width: width,
            height: height
        )
    }

    /// Always animated: the backdrop and caption should fade regardless, and
    /// the image subtree opts out of movement itself under Reduce Motion.
    private func close() {
        withAnimation(.smooth) {
            expanded = false
        } completion: {
            lightbox.close()
        }
    }
}
