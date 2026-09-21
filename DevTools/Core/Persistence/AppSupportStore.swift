import Foundation
import os

/// Small JSON files under Application Support. Failures are logged, not thrown:
/// nothing persisted here is load-bearing for correctness, only for convenience.
enum AppSupportStore {
    private static let log = Logger(subsystem: "mldgg.devtools", category: "persistence")

    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appending(path: "dev-tools", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func load<T: Decodable>(_ type: T.Type, name: String) -> T? {
        let url = directory.appending(path: name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            log.error("Failed to decode \(name): \(error.localizedDescription)")
            return nil
        }
    }

    static func save<T: Encodable>(_ value: T, name: String) {
        let url = directory.appending(path: name)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(value).write(to: url, options: .atomic)
        } catch {
            log.error("Failed to save \(name): \(error.localizedDescription)")
        }
    }
}
