import Foundation

/// Plex's numeric metadata types: the spec's "List of Metadata Types". The
/// spec keeps it in prose rather than as a schema enum, so it's restated here;
/// `MetadataTypeTests` holds it to the bundled spec's table.
enum MetadataType {
    static let numbers: [String: Int] = [
        "movie": 1, "show": 2, "season": 3, "episode": 4, "trailer": 5, "person": 7,
        "artist": 8, "album": 9, "track": 10, "clip": 12, "photo": 13, "photoalbum": 14,
        "playlist": 15, "playlistfolder": 16, "collection": 18,
    ]

    static let names: [Int: String] = Dictionary(uniqueKeysWithValues: numbers.map { ($1, $0) })

    /// Every type, by number.
    static let all: [(number: Int, name: String)] = names.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }

    /// `movie (1)` for a number the table knows; nil for anything else,
    /// including names, which already read as themselves.
    static func label(_ value: String) -> String? {
        guard let number = Int(value), let name = names[number] else { return nil }
        return label(number: number, name: name)
    }

    static func label(number: Int, name: String) -> String {
        "\(name) (\(number))"
    }
}
