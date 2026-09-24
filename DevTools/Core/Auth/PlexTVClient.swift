import Foundation

struct PlexPIN: Sendable, Decodable, Hashable {
    let id: Int
    let code: String
    let authToken: String?
}

struct PlexUser: Sendable, Decodable, Hashable {
    let id: Int
    let uuid: String
    let username: String
    let title: String
    let email: String?
    let thumb: String?

    var thumbURL: URL? { thumb.flatMap(URL.init(string:)) }
}

enum PlexTVError: Error, LocalizedError {
    case status(Int)
    case nonHTTPResponse

    var errorDescription: String? {
        switch self {
        case .status(let code): "plex.tv returned HTTP \(code)."
        case .nonHTTPResponse: "plex.tv returned a non-HTTP response."
        }
    }
}

struct PlexTVClient: Sendable {
    static let host = URL(string: "https://plex.tv")!

    private let session: URLSession
    private let identity: ClientIdentity

    init(identity: ClientIdentity) {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20
        self.session = URLSession(configuration: config, delegate: SameOriginRedirects(), delegateQueue: nil)
        self.identity = identity
    }

    func createPIN() async throws -> PlexPIN {
        var components = URLComponents(url: Self.host.appending(path: "api/v2/pins"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "strong", value: "true")]
        var request = makeRequest(components.url!)
        request.httpMethod = "POST"
        return try await decode(PlexPIN.self, from: request)
    }

    func pollPIN(id: Int) async throws -> PlexPIN {
        let request = makeRequest(Self.host.appending(path: "api/v2/pins/\(id)"))
        return try await decode(PlexPIN.self, from: request)
    }

    func approvalURL(for pin: PlexPIN) -> URL {
        var fragment = URLComponents()
        fragment.queryItems = [
            URLQueryItem(name: "clientID", value: identity.clientIdentifier),
            URLQueryItem(name: "code", value: pin.code),
            URLQueryItem(name: "context[device][product]", value: identity.product),
            URLQueryItem(name: "context[device][deviceName]", value: identity.deviceName),
        ]
        var url = URLComponents(string: "https://app.plex.tv/auth")!
        url.fragment = "?" + (fragment.percentEncodedQuery ?? "")
        return url.url!
    }

    func currentUser(token: String) async throws -> PlexUser {
        let request = makeRequest(Self.host.appending(path: "api/v2/user"), token: token)
        return try await decode(PlexUser.self, from: request)
    }

    func resources(token: String) async throws -> [PlexResource] {
        var components = URLComponents(url: Self.host.appending(path: "api/v2/resources"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "includeHttps", value: "1"),
            URLQueryItem(name: "includeRelay", value: "1"),
            URLQueryItem(name: "includeIPv6", value: "1"),
        ]
        let request = makeRequest(components.url!, token: token)
        return try await decode([PlexResource].self, from: request)
    }

    /// Uses the legacy XML `/api/users`: `/api/v2/friends` has been retired.
    func friendAvatars(token: String) async throws -> [Int: URL] {
        var request = makeRequest(Self.host.appending(path: "api/users"), token: token)
        request.setValue("application/xml", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PlexTVError.nonHTTPResponse }
        guard (200..<300).contains(http.statusCode) else { throw PlexTVError.status(http.statusCode) }
        guard let root = XMLNodeParser.parse(data) else { return [:] }
        var avatars: [Int: URL] = [:]
        for user in root.children where user.name == "User" {
            if let id = user["id"].flatMap(Int.init), let thumb = user["thumb"], let url = URL(string: thumb) {
                avatars[id] = url
            }
        }
        return avatars
    }

    private func makeRequest(_ url: URL, token: String? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (name, value) in identity.headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if let token {
            request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
        }
        return request
    }

    private func decode<T: Decodable>(_ type: T.Type, from request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PlexTVError.nonHTTPResponse }
        guard (200..<300).contains(http.statusCode) else { throw PlexTVError.status(http.statusCode) }
        return try JSONDecoder().decode(type, from: data)
    }
}
