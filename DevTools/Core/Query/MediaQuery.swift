import Foundation

/// The field types of the spec's media query language. Operators are
/// defined per type; the characters before an operator's trailing `=` are
/// appended to the field name in the query string (`year>>=2000`), which
/// the spec notes must be URI-encoded on the key side.
enum MediaFieldType: Hashable, Sendable {
    case integer, boolean, tag, string, date, language
    case other(String)

    init(raw: String) {
        switch raw {
        case "integer": self = .integer
        case "boolean": self = .boolean
        case "tag": self = .tag
        case "string": self = .string
        case "date": self = .date
        case "language": self = .language
        default: self = .other(raw)
        }
    }

    var operators: [MediaOperator] {
        switch self {
        case .integer: [
            MediaOperator("=", "is"), MediaOperator("!=", "is not"),
            MediaOperator(">>=", "is greater than"), MediaOperator("<<=", "is less than"),
            MediaOperator(">=", "is at least"), MediaOperator("<=", "is at most"),
        ]
        case .boolean: [MediaOperator("=", "is")]
        case .tag: [MediaOperator("=", "is"), MediaOperator("!=", "is not")]
        case .string: [
            MediaOperator("=", "contains"), MediaOperator("!=", "does not contain"),
            MediaOperator("==", "is"), MediaOperator("!==", "is not"),
            MediaOperator("<=", "begins with"), MediaOperator(">=", "ends with"),
        ]
        case .date: [
            MediaOperator("=", "is"), MediaOperator("!=", "is not"),
            MediaOperator(">>=", "is after"), MediaOperator("<<=", "is before"),
        ]
        case .language, .other: [MediaOperator("=", "is"), MediaOperator("!=", "is not")]
        }
    }

    var valuePrompt: String {
        switch self {
        case .integer: "number"
        case .boolean: ""
        case .tag: "tag id"
        case .string: "text"
        case .date: "epoch, or -3y / -2w / -7d"
        case .language: "ISO 639-2 code"
        case .other: "value"
        }
    }
}

struct MediaOperator: Hashable, Sendable, Identifiable {
    var id: String { key }
    let key: String
    let title: String

    init(_ key: String, _ title: String) {
        self.key = key
        self.title = title
    }
}

struct MediaField: Hashable, Sendable, Identifiable {
    var id: String { key }
    let key: String
    let title: String
    let type: MediaFieldType
}

struct MediaSortField: Hashable, Sendable, Identifiable {
    var id: String { key }
    let key: String
    let title: String
}

/// A field whose values the server can list: the spec's `Filter` element,
/// whose `key` is the endpoint returning the possible values.
struct MediaFilter: Hashable, Sendable, Identifiable {
    var id: String { filter }
    /// The query key; matches the `MediaField.key` it enumerates.
    let filter: String
    let title: String
    /// Endpoint listing the values (`/library/sections/1/studio?type=1`).
    let valuesKey: String
}

/// One possible value of a filter. `key` is what the query takes (a tag id
/// for tag fields, the value itself otherwise); `title` is what people read.
struct MediaFilterValue: Hashable, Sendable, Identifiable {
    var id: String { key }
    let key: String
    let title: String

    /// Values from a filter endpoint's `Directory` items.
    static func parse(root: Node) -> [MediaFilterValue] {
        root.children.compactMap { item in
            guard let key = item["key"], !key.isEmpty else { return nil }
            return MediaFilterValue(key: key, title: item["title"] ?? key)
        }
    }

    /// When every key is its own title the field takes the text directly
    /// (studio, year); otherwise the keys are ids and a value must be picked.
    static func keysAreValues(_ values: [MediaFilterValue]) -> Bool {
        !values.isEmpty && values.allSatisfy { $0.key == $0.title }
    }
}

struct MediaType: Hashable, Sendable, Identifiable {
    var id: Int { number }
    let number: Int
    let name: String
    let title: String
    let fields: [MediaField]
    let sorts: [MediaSortField]
    let filters: [MediaFilter]

    /// The filter enumerating `fieldKey`'s values, if the server lists them.
    func filter(for fieldKey: String) -> MediaFilter? {
        filters.first { $0.filter == fieldKey }
    }

    /// The spec's "List of Metadata Types", used when a `Type` element's key
    /// doesn't carry `type=N`.
    static let numbers: [String: Int] = [
        "movie": 1, "show": 2, "season": 3, "episode": 4, "trailer": 5, "person": 7,
        "artist": 8, "album": 9, "track": 10, "clip": 12, "photo": 13, "photoalbum": 14,
        "playlist": 15, "playlistfolder": 16, "collection": 18,
    ]
}

/// The types, fields, sorts, and filters a library section supports, from
/// `/library/sections/{id}?includeDetails=1`. The spec documents the query
/// language but not these elements, so parsing is tolerant: anything missing
/// yields an empty list rather than a failure.
struct SectionDetails: Hashable, Sendable {
    let types: [MediaType]

    init(root: Node) {
        types = root.children.filter { $0.name == "Type" }.compactMap { node in
            guard let name = node["type"] else { return nil }
            let fromKey = node["key"]
                .flatMap { PlexRequest.splitPath($0).query.first { $0.name == "type" }?.value }
                .flatMap(Int.init)
            guard let number = fromKey ?? MediaType.numbers[name] else { return nil }
            let fields = node.children.filter { $0.name == "Field" }.compactMap { field -> MediaField? in
                guard let key = field["key"] else { return nil }
                return MediaField(key: key, title: field["title"] ?? key, type: MediaFieldType(raw: field["type"] ?? "string"))
            }
            let sorts = node.children.filter { $0.name == "Sort" }.compactMap { sort -> MediaSortField? in
                guard let key = sort["key"] else { return nil }
                return MediaSortField(key: key, title: sort["title"] ?? key)
            }
            let filters = node.children.filter { $0.name == "Filter" }.compactMap { filter -> MediaFilter? in
                guard let name = filter["filter"], let key = filter["key"], !key.isEmpty else { return nil }
                return MediaFilter(filter: name, title: filter["title"] ?? name, valuesKey: key)
            }
            return MediaType(number: number, name: name, title: node["title"] ?? name.capitalized, fields: fields, sorts: sorts, filters: filters)
        }
    }
}

/// A query under construction. `request()` emits it in the documented
/// querystring language against `/library/sections/{section}/all`.
struct MediaQuery: Hashable, Sendable {
    struct Term: Hashable, Sendable, Identifiable {
        var id = UUID()
        var field: String
        var fieldType: MediaFieldType
        var operatorKey: String
        var value: String
        /// What the picked value is called, when `value` is an id the user
        /// never typed. Display only; never emitted.
        var label = ""

        init(field: MediaField) {
            self.field = field.key
            self.fieldType = field.type
            self.operatorKey = field.type.operators.first?.key ?? "="
            self.value = field.type == .boolean ? "1" : ""
        }

        /// Booleans are always live; everything else needs a value.
        var isActive: Bool {
            fieldType == .boolean || !value.trimmingCharacters(in: .whitespaces).isEmpty
        }

        var queryParam: QueryParam {
            if fieldType == .boolean {
                return QueryParam(name: field, value: value == "0" ? "0" : "1")
            }
            let suffix = operatorKey.hasSuffix("=") ? String(operatorKey.dropLast()) : operatorKey
            return QueryParam(name: field + suffix, value: value.trimmingCharacters(in: .whitespaces))
        }
    }

    struct Sort: Hashable, Sendable, Identifiable {
        var id = UUID()
        var key: String
        var descending = false

        var token: String { descending ? "\(key):desc" : key }
    }

    /// One node of the filter tree: a leaf condition or a parenthesized
    /// subgroup. Subgroups emit `push=1` … `pop=1` around their contents.
    enum Node: Hashable, Sendable, Identifiable {
        case term(Term)
        case group(Group)

        var id: UUID {
            switch self {
            case .term(let term): term.id
            case .group(let group): group.id
            }
        }
    }

    /// A parenthesized set of nodes. `matchAny` joins them with `or=1`;
    /// otherwise they AND together.
    struct Group: Hashable, Sendable, Identifiable {
        var id = UUID()
        var matchAny = false
        var children: [Node] = []
    }

    var sectionKey = ""
    var type = 0
    var root = Group()
    var sorts: [Sort] = []
    var group = ""
    var limit = ""

    var hasSection: Bool { !sectionKey.isEmpty }
    var path: String { "/library/sections/\(sectionKey)/all" }

    var queryParams: [QueryParam] {
        var params = [QueryParam(name: "type", value: String(type))]
        params += clauseParams(root)
        if !sorts.isEmpty {
            params.append(QueryParam(name: "sort", value: sorts.map(\.token).joined(separator: ",")))
        }
        let group = group.trimmingCharacters(in: .whitespaces)
        if !group.isEmpty { params.append(QueryParam(name: "group", value: group)) }
        let limit = limit.trimmingCharacters(in: .whitespaces)
        if !limit.isEmpty { params.append(QueryParam(name: "limit", value: limit)) }
        return params
    }

    /// Walks a group in order: active terms emit their param, non-empty
    /// subgroups emit `push=1` … `pop=1`, and `or=1` precedes every sibling
    /// after the first when the group matches any.
    private func clauseParams(_ clause: Group) -> [QueryParam] {
        var params: [QueryParam] = []
        var emitted = 0
        for node in clause.children {
            let nodeParams: [QueryParam]
            switch node {
            case .term(let term):
                guard term.isActive else { continue }
                nodeParams = [term.queryParam]
            case .group(let child):
                let inner = clauseParams(child)
                guard !inner.isEmpty else { continue }
                nodeParams = [QueryParam(name: "push", value: "1")] + inner + [QueryParam(name: "pop", value: "1")]
            }
            if emitted > 0, clause.matchAny { params.append(QueryParam(name: "or", value: "1")) }
            params += nodeParams
            emitted += 1
        }
        return params
    }

    mutating func pruneTerms(keepingFields fields: Set<String>) {
        root.children = MediaQuery.prunedChildren(root.children, keepingFields: fields)
    }

    private static func prunedChildren(_ children: [Node], keepingFields fields: Set<String>) -> [Node] {
        children.compactMap { node in
            switch node {
            case .term(let term):
                return fields.contains(term.field) ? node : nil
            case .group(let group):
                let kept = prunedChildren(group.children, keepingFields: fields)
                return kept.isEmpty ? nil : .group(Group(id: group.id, matchAny: group.matchAny, children: kept))
            }
        }
    }

    func request() -> PlexRequest {
        var request = PlexRequest(path: path)
        request.query = queryParams
        return request
    }
}
