import SwiftUI

/// Server artwork at a fixed point size, loaded through `ImageStore` (token as
/// a header). Fills and crops by default; `fit` letterboxes the whole image.
/// Shows `placeholder` until it arrives or if it can't.
struct RemoteImage<Placeholder: View>: View {
    let value: String?
    let server: ConnectedServer?
    let size: CGSize
    var fit = false
    @ViewBuilder let placeholder: () -> Placeholder

    @Environment(ImageStore.self) private var images
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: PlatformImage?

    var body: some View {
        ZStack {
            if let image {
                if fit {
                    Image(platformImage: image).resizable().scaledToFit().transition(.opacity)
                } else {
                    Image(platformImage: image).resizable().scaledToFill().transition(.opacity)
                }
            } else {
                placeholder()
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .task(id: "\(server?.machineID ?? "")|\(value ?? "")|\(Int(size.width))x\(Int(size.height))") {
            guard let value, let server else { image = nil; return }
            let pw = Int(size.width * 2), ph = Int(size.height * 2)
            if let cached = images.cachedImage(for: value, server: server, width: pw, height: ph) {
                image = cached
                return
            }
            image = nil
            let loaded = await images.image(for: value, server: server, width: pw, height: ph)
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) { image = loaded }
        }
        // Lazy containers keep created cells alive, so drop the decoded image
        // when scrolled away; ImageStore's cache makes the return instant.
        .onDisappear { image = nil }
    }
}
