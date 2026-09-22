import Observation
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Loads server artwork through `PlexHTTP`, so the token travels as a header
/// and never appears in an image URL. Server-relative paths go through
/// `/photo/:/transcode` at the requested pixel size; absolute URLs (public
/// CDN art) are fetched as-is without credentials. Decoded images are cached
/// in memory per server, path, and size.
@MainActor
@Observable
final class ImageStore {
    private let http: PlexHTTP
    private let cache = NSCache<NSString, PlatformImage>()
    private var inFlight: [String: Task<Data?, Never>] = [:]

    init(http: PlexHTTP) {
        self.http = http
        // Bounded by decoded bytes, not count: a 2× poster is ~400 KB, so a
        // count limit alone lets a big library scroll into hundreds of MB.
        cache.totalCostLimit = 160 * 1024 * 1024
    }

    private func cacheKey(_ value: String, _ server: ConnectedServer, _ width: Int, _ height: Int) -> NSString {
        "\(server.machineID)|\(value)|\(width)x\(height)" as NSString
    }

    /// The decoded image if it's already in memory, without touching the
    /// network. Lets a view show a cached hit instantly and reserve the fade
    /// for a real decode.
    func cachedImage(for value: String, server: ConnectedServer, width: Int, height: Int) -> PlatformImage? {
        cache.object(forKey: cacheKey(value, server, width, height))
    }

    func image(for value: String, server: ConnectedServer, width: Int, height: Int) async -> PlatformImage? {
        let key = cacheKey(value, server, width, height)
        if let cached = cache.object(forKey: key) { return cached }

        let task = inFlight[key as String] ?? Task<Data?, Never> { [http] in
            if value.contains("://") {
                guard let url = URL(string: value), let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
                return data
            }
            var request = PlexRequest(path: "/photo/:/transcode")
            request.query = [
                QueryParam(name: "url", value: value),
                QueryParam(name: "width", value: String(width)),
                QueryParam(name: "height", value: String(height)),
                QueryParam(name: "minSize", value: "1"),
            ]
            request.headers = [HeaderField(name: "Accept", value: "image/*")]
            guard let response = try? await http.send(request, to: server), response.status == 200 else { return nil }
            return response.body
        }
        inFlight[key as String] = task
        let data = await task.value
        inFlight[key as String] = nil

        guard let data, let image = PlatformImage(data: data) else { return nil }
        cache.setObject(image, forKey: key, cost: width * height * 4)
        return image
    }
}
