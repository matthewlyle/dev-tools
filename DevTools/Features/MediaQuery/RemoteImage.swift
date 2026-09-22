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
    @State private var image: PlatformImage?

    var body: some View {
        ZStack {
            if let image {
                if fit {
                    Image(platformImage: image).resizable().scaledToFit()
                } else {
                    Image(platformImage: image).resizable().scaledToFill()
                }
            } else {
                placeholder()
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .task(id: "\(server?.machineID ?? "")|\(value ?? "")|\(Int(size.width))x\(Int(size.height))") {
            image = nil
            guard let value, let server else { return }
            image = await images.image(for: value, server: server, width: Int(size.width * 2), height: Int(size.height * 2))
        }
        // Lazy containers keep created cells alive, so drop the decoded image
        // when scrolled away; ImageStore's cache makes the return instant.
        .onDisappear { image = nil }
    }
}
