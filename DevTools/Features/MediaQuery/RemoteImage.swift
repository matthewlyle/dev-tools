import SwiftUI

/// Server artwork fetched at `size` points for the screen's scale, loaded
/// through `ImageStore` (token as a header). The caller frames it; it fills
/// and crops by default, and `fit` letterboxes the whole image. Shows
/// `placeholder` until it arrives or if it can't.
struct RemoteImage<Placeholder: View>: View {
    let value: String?
    let server: ConnectedServer?
    let size: CGSize
    var fit = false
    @ViewBuilder let placeholder: () -> Placeholder

    @Environment(ImageStore.self) private var images
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: "\(server?.machineID ?? "")|\(value ?? "")|\(Int(size.width))x\(Int(size.height))@\(displayScale)") {
            guard let value, let server else { image = nil; return }
            let pw = Int((size.width * displayScale).rounded()), ph = Int((size.height * displayScale).rounded())
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
