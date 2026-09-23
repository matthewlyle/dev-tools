import SwiftUI

/// Server artwork fetched at `size` points for the screen's scale, loaded
/// through `ImageStore` (token as a header). The caller frames it; it fills
/// and crops by default, and `fit` letterboxes the whole image. Shows
/// `placeholder` until it arrives or if it can't, told which: `loading` is
/// false once there's nothing more to wait for (no art, or the fetch failed).
struct RemoteImage<Placeholder: View>: View {
    let value: String?
    let server: ConnectedServer?
    let size: CGSize
    var fit = false
    @ViewBuilder let placeholder: (_ loading: Bool) -> Placeholder

    @Environment(ImageStore.self) private var images
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @State private var image: PlatformImage?
    @State private var loading = true

    /// The clear base takes exactly the size offered and the image fills it
    /// as an overlay: a scaled-to-fill image reports more than it was
    /// offered, and a flexible frame around it would grow to match, so the
    /// crop would land outside the tile.
    var body: some View {
        Color.clear
            .overlay {
                if let image {
                    if fit {
                        Image(platformImage: image).resizable().scaledToFit().transition(.opacity)
                    } else {
                        Image(platformImage: image).resizable().scaledToFill().transition(.opacity)
                    }
                } else {
                    placeholder(loading)
                }
            }
            .clipped()
            .task(id: "\(server?.machineID ?? "")|\(value ?? "")|\(Int(size.width))x\(Int(size.height))@\(displayScale)") {
                guard let value, let server else {
                    image = nil
                    loading = false
                    return
                }
                let pw = Int((size.width * displayScale).rounded()), ph = Int((size.height * displayScale).rounded())
                if let cached = images.cachedImage(for: value, server: server, width: pw, height: ph) {
                    image = cached
                    return
                }
                image = nil
                loading = true
                let loaded = await images.image(for: value, server: server, width: pw, height: ph)
                guard !Task.isCancelled else { return }
                loading = false
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) { image = loaded }
            }
            // Lazy containers keep created cells alive, so drop the decoded image
            // when scrolled away; ImageStore's cache makes the return instant.
            .onDisappear { image = nil }
    }
}
