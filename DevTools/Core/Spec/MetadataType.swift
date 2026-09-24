import Foundation

/// The spec lists these in prose, not as a schema enum, so they're restated here;
/// `MetadataTypeTests` holds them to the bundled spec's table.
enum MetadataType {
    static let numbers: [String: Int] = [
        "movie": 1, "show": 2, "season": 3, "episode": 4, "trailer": 5, "person": 7,
        "artist": 8, "album": 9, "track": 10, "clip": 12, "photo": 13, "photoalbum": 14,
        "playlist": 15, "playlistfolder": 16, "collection": 18,
    ]

    static let names: [Int: String] = Dictionary(uniqueKeysWithValues: numbers.map { ($1, $0) })

    static let all: [(number: Int, name: String)] = names.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }

    static func label(_ value: String) -> String? {
        guard let number = Int(value), let name = names[number] else { return nil }
        return label(number: number, name: name)
    }

    static func label(number: Int, name: String) -> String {
        "\(name) (\(number))"
    }
}
