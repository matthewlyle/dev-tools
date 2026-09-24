import Observation
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
@Observable
final class ImageStore {
    private let http: PlexHTTP
    private let publicSession: URLSession
    private let cache = NSCache<NSString, PlatformImage>()
    private var inFlight: [String: Task<Data?, Never>] = [:]
    @ObservationIgnored private var generation = 0

    init(http: PlexHTTP) {
        self.http = http
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        publicSession = URLSession(configuration: config)
        // Bounded by decoded bytes, not count: a count limit alone lets a big
        // library scroll into hundreds of MB.
        cache.totalCostLimit = 160 * 1024 * 1024
    }

    private func cacheKey(_ value: String, _ server: ConnectedServer, _ width: Int, _ height: Int) -> NSString {
        "\(server.machineID)|\(value)|\(width)x\(height)" as NSString
    }

    func removeAll() {
        generation += 1
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
        cache.removeAllObjects()
    }

    func cachedImage(for value: String, server: ConnectedServer, width: Int, height: Int) -> PlatformImage? {
        cache.object(forKey: cacheKey(value, server, width, height))
    }

    func image(for value: String, server: ConnectedServer, width: Int, height: Int) async -> PlatformImage? {
        await load(key: cacheKey(value, server, width, height), cost: width * height * 4) { [http, publicSession] in
            if value.contains("://") {
                guard let url = URL(string: value) else { return nil }
                return try? await publicSession.data(from: url).0
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
    }

    func image(at url: URL, width: Int, height: Int) async -> PlatformImage? {
        await load(key: "public|\(url.absoluteString)|\(width)x\(height)" as NSString, cost: width * height * 4) { [publicSession] in
            try? await publicSession.data(from: url).0
        }
    }

    private func load(key: NSString, cost: Int, fetch: @escaping @Sendable () async -> Data?) async -> PlatformImage? {
        if let cached = cache.object(forKey: key) { return cached }

        let generation = generation
        let task = inFlight[key as String] ?? Task<Data?, Never> { await fetch() }
        inFlight[key as String] = task
        let data = await task.value
        guard generation == self.generation else { return nil }
        inFlight[key as String] = nil

        guard let data, let image = PlatformImage(data: data) else { return nil }
        cache.setObject(image, forKey: key, cost: cost)
        return image
    }
}
