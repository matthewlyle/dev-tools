import Foundation

struct SpecParameter: Sendable, Hashable, Identifiable {
    enum Location: String, Sendable {
        case path, query, header
    }

    var id: String { "\(location.rawValue):\(name)" }

    let name: String
    let location: Location
    let description: String?
    let required: Bool
    let type: String?
    let enumValues: [String]
    let defaultValue: String?
    let example: String?

    var suggestedValue: String {
        defaultValue ?? example ?? enumValues.first ?? ""
    }
}

struct SpecOperation: Sendable, Hashable, Identifiable {
    var id: String { template }

    let template: String
    let tag: String
    let operationID: String?
    let summary: String
    let description: String?
    let parameters: [SpecParameter]
    /// Accepts the media-query filtering language (`#/components/parameters/mediaQuery`).
    let supportsMediaQuery: Bool

    /// developer.plex.tv is a stock Redoc site, whose deep links are
    /// `#tag/<tag>/operation/<operationId>` — both fields the spec already
    /// carries, so links are derived, never authored.
    static let docsBase = URL(string: "https://developer.plex.tv/pms/")!

    var docsURL: URL? {
        guard let operationID,
              let tag = tag.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }
        return URL(string: "#tag/\(tag)/operation/\(operationID)", relativeTo: Self.docsBase)?.absoluteURL
    }

    var pathParameters: [SpecParameter] { parameters.filter { $0.location == .path } }
    var queryParameters: [SpecParameter] { parameters.filter { $0.location == .query } }
    var headerParameters: [SpecParameter] { parameters.filter { $0.location == .header } }

    var placeholders: [String] {
        var result: [String] = []
        var rest = template[...]
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            result.append(String(rest[rest.index(after: open)..<close]))
            rest = rest[rest.index(after: close)...]
        }
        return result
    }

    func path(filling values: [String: String]) -> String {
        var result = template
        for (name, value) in values where !value.isEmpty {
            result = result.replacingOccurrences(of: "{\(name)}", with: value)
        }
        return result
    }

    /// Whether `path` (no query) is an instance of this template. Compared
    /// segment by segment; placeholders match any non-empty run within a
    /// segment, and `.*` (the transcoder's `start.*`) matches any suffix.
    func matches(_ path: String) -> Bool {
        let templateSegments = template.split(separator: "/", omittingEmptySubsequences: false)
        let pathSegments = path.split(separator: "/", omittingEmptySubsequences: false)
        guard templateSegments.count == pathSegments.count else { return false }
        return zip(templateSegments, pathSegments).allSatisfy { Self.segmentMatches($0, $1) }
    }

    private static func segmentMatches(_ template: Substring, _ segment: Substring) -> Bool {
        if template.hasSuffix(".*") {
            return segment.hasPrefix(template.dropLast(2))
        }
        guard template.contains("{") else { return template == segment }

        // Split into the literal pieces between placeholders, e.g.
        // "tv.plex.providers.epg.{identifier}:{deviceId}" → ["tv.plex.providers.epg.", ":", ""].
        var literals: [Substring] = []
        var rest = template
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            literals.append(rest[..<open])
            rest = rest[rest.index(after: close)...]
        }
        literals.append(rest)

        guard segment.hasPrefix(literals[0]) else { return false }
        var cursor = segment.index(segment.startIndex, offsetBy: literals[0].count)
        for literal in literals.dropFirst() {
            // The placeholder before this literal must consume at least one character.
            guard cursor < segment.endIndex else { return false }
            let searchStart = segment.index(after: cursor)
            if literal.isEmpty {
                cursor = segment.endIndex
                continue
            }
            guard let range = segment[searchStart...].range(of: literal) else { return false }
            cursor = range.upperBound
        }
        return cursor == segment.endIndex
    }
}

struct SpecCatalog: Sendable {
    struct TagGroup: Sendable, Identifiable {
        var id: String { name }
        let name: String
        let operations: [SpecOperation]
    }

    let version: String
    let operations: [SpecOperation]
    let groups: [TagGroup]
    let documentedHeaders: [SpecParameter]

    init(spec: OpenAPISpec) {
        version = spec.info.version.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = spec.components?.parameters ?? [:]

        var operations: [SpecOperation] = []
        operations.reserveCapacity(spec.paths.count)

        for (template, item) in spec.paths {
            guard let get = item.get else { continue }
            var supportsMediaQuery = false
            var parameters: [SpecParameter] = []
            var seen = Set<String>()

            for entry in (item.parameters ?? []) + (get.parameters ?? []) {
                let resolved: OpenAPISpec.Parameter?
                switch entry {
                case .ref(let ref):
                    let key = ref.split(separator: "/").last.map(String.init) ?? ""
                    if key == "mediaQuery" { supportsMediaQuery = true }
                    resolved = components[key]
                case .parameter(let parameter):
                    resolved = parameter
                }
                guard let resolved, let flattened = Self.flatten(resolved) else { continue }
                if seen.insert(flattened.id).inserted { parameters.append(flattened) }
            }

            operations.append(SpecOperation(
                template: template,
                tag: get.tags?.first ?? "Other",
                operationID: get.operationId,
                summary: get.summary ?? template,
                description: get.description,
                parameters: parameters,
                supportsMediaQuery: supportsMediaQuery
            ))
        }

        operations.sort { $0.template < $1.template }
        self.operations = operations

        var order: [String] = []
        var buckets: [String: [SpecOperation]] = [:]
        for operation in operations {
            if buckets[operation.tag] == nil { order.append(operation.tag) }
            buckets[operation.tag, default: []].append(operation)
        }
        groups = order.sorted().map { TagGroup(name: $0, operations: buckets[$0]!) }

        var headers: [SpecParameter] = Self.paginationHeaders
        var headerNames = Set(headers.map(\.name))
        for parameter in operations.flatMap(\.headerParameters) where headerNames.insert(parameter.name).inserted {
            headers.append(parameter)
        }
        documentedHeaders = headers.sorted { $0.name < $1.name }
    }

    func match(path: String) -> SpecOperation? {
        let pure = PlexRequest.splitPath(path).path
        let trimmed = pure.count > 1 && pure.hasSuffix("/") ? String(pure.dropLast()) : pure
        return operations
            .filter { $0.matches(trimmed) }
            .min { $0.placeholders.count < $1.placeholders.count }
    }

    func groups(matching needle: String) -> [TagGroup] {
        let needle = needle.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return groups }
        return groups.compactMap { group in
            if group.name.localizedCaseInsensitiveContains(needle) { return group }
            let hits = group.operations.filter {
                $0.template.localizedCaseInsensitiveContains(needle)
                    || $0.summary.localizedCaseInsensitiveContains(needle)
            }
            return hits.isEmpty ? nil : TagGroup(name: group.name, operations: hits)
        }
    }

    /// Operations whose path takes `placeholder`, most specific first (fewest
    /// other placeholders), then by template.
    func operations(taking placeholder: String) -> [SpecOperation] {
        operations
            .filter { $0.placeholders.contains(placeholder) }
            .sorted { a, b in
                a.placeholders.count != b.placeholders.count
                    ? a.placeholders.count < b.placeholders.count
                    : a.template < b.template
            }
    }

    private static func flatten(_ parameter: OpenAPISpec.Parameter) -> SpecParameter? {
        let location: SpecParameter.Location
        switch parameter.in {
        case "path": location = .path
        case "header": location = .header
        case "query", nil: location = .query
        default: return nil
        }
        return SpecParameter(
            name: parameter.name,
            location: location,
            description: parameter.description ?? parameter.schema?.description,
            required: parameter.required ?? (location == .path),
            type: parameter.schema?.type,
            enumValues: parameter.schema?.enum?.map(\.text) ?? [],
            defaultValue: parameter.schema?.default?.text,
            example: parameter.example?.text ?? parameter.schema?.example?.text
        )
    }

    private static let paginationHeaders: [SpecParameter] = [
        SpecParameter(name: "X-Plex-Container-Start", location: .header, description: "Offset of the first item to return.", required: false, type: "integer", enumValues: [], defaultValue: nil, example: "0"),
        SpecParameter(name: "X-Plex-Container-Size", location: .header, description: "Number of items to return. Size 0 returns only the total count.", required: false, type: "integer", enumValues: [], defaultValue: nil, example: "50"),
        SpecParameter(name: "X-Plex-Container-Focus-Key", location: .header, description: "Center the page on this item's key instead of using a start offset.", required: false, type: "string", enumValues: [], defaultValue: nil, example: nil),
        SpecParameter(name: "X-Plex-Pms-Api-Version", location: .header, description: "API contract version. 1.0 requires PMS ≥ 1.41.9; unset means legacy 0.0 (e.g. `includeFields` semantics differ).", required: false, type: "string", enumValues: ["1.0"], defaultValue: nil, example: "1.0"),
    ]
}
