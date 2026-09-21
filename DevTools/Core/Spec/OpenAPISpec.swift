import Foundation

struct OpenAPISpec: Decodable, Sendable {
    struct Info: Decodable, Sendable {
        let title: String
        let version: String
    }

    struct PathItem: Decodable, Sendable {
        let get: Operation?
        let parameters: [ParameterOrRef]?
    }

    struct Operation: Decodable, Sendable {
        let operationId: String?
        let summary: String?
        let description: String?
        let tags: [String]?
        let parameters: [ParameterOrRef]?
        /// Security requirements; scheme name → scopes. `[[:]]` means none.
        let security: [[String: [String]]]?
    }

    enum ParameterOrRef: Decodable, Sendable {
        case ref(String)
        case parameter(Parameter)

        private enum Keys: String, CodingKey {
            case ref = "$ref"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Keys.self)
            if let ref = try container.decodeIfPresent(String.self, forKey: .ref) {
                self = .ref(ref)
            } else {
                self = .parameter(try Parameter(from: decoder))
            }
        }
    }

    struct Parameter: Decodable, Sendable {
        let name: String
        let `in`: String?
        let description: String?
        let required: Bool?
        let schema: Schema?
        let example: LossyScalar?
    }

    struct Schema: Decodable, Sendable {
        let type: String?
        let `enum`: [LossyScalar]?
        let `default`: LossyScalar?
        let example: LossyScalar?
        let description: String?
    }

    struct Components: Decodable, Sendable {
        let parameters: [String: Parameter]?
    }

    let info: Info
    let paths: [String: PathItem]
    let components: Components?
    /// Document-wide security requirement, inherited by operations that don't override it.
    let security: [[String: [String]]]?

    static func loadBundled() throws -> OpenAPISpec {
        guard let url = Bundle.main.url(forResource: "plex-openapi", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(OpenAPISpec.self, from: Data(contentsOf: url))
    }
}

/// A JSON scalar of any type, kept as its display string. Spec `enum`,
/// `default`, and `example` values mix strings, numbers, and booleans.
struct LossyScalar: Decodable, Sendable, Hashable {
    let text: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            text = string
        } else if let int = try? container.decode(Int.self) {
            text = String(int)
        } else if let double = try? container.decode(Double.self) {
            text = String(double)
        } else if let bool = try? container.decode(Bool.self) {
            text = bool ? "1" : "0"
        } else {
            text = ""
        }
    }
}
