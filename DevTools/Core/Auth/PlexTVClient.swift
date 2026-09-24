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
    case unreadable

    var errorDescription: String? {
        switch self {
        case .status(let code): "plex.tv returned HTTP \(code)."
        case .nonHTTPResponse: "plex.tv returned a non-HTTP response."
        case .unreadable: "plex.tv returned a response the app couldn't read."
        }
    }
}

struct PlexTVClient: Sendable {
    static let host = URL(string: "https://clients.plex.tv")!

    /// The device JWT's issuer.
    var clientIdentifier: String { identity.clientIdentifier }

    private let session: URLSession
    private let identity: ClientIdentity

    init(identity: ClientIdentity) {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20
        self.session = URLSession(configuration: config)
        self.identity = identity
    }

    /// A strong PIN carrying the device's public key, so the token it's
    /// exchanged for is a Plex JWT bound to this install.
    func createPIN(jwk: [String: String]) async throws -> PlexPIN {
        var request = makeRequest(Self.host.appending(path: "api/v2/pins"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["jwk": jwk, "strong": true])
        return try await decode(PlexPIN.self, from: request)
    }

    /// The PIN, with the Plex JWT in `authToken` once it's approved. Asked
    /// for as XML: with a device JWT the JSON response leaves the token out.
    func pollPIN(id: Int, deviceJWT: String) async throws -> PlexPIN {
        var components = URLComponents(url: Self.host.appending(path: "api/v2/pins/\(id)"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "deviceJWT", value: deviceJWT)]
        var request = makeRequest(components.url!)
        request.setValue("application/xml", forHTTPHeaderField: "Accept")
        let root = try await xml(from: request)
        guard let id = root["id"].flatMap(Int.init), let code = root["code"] else { throw PlexTVError.unreadable }
        return PlexPIN(id: id, code: code, authToken: root["authToken"].flatMap { $0.isEmpty ? nil : $0 })
    }

    /// Registers the device's public key with a legacy token, so an existing
    /// sign-in can move to JWTs without signing in again.
    func registerKey(jwk: [String: String], token: String) async throws {
        var request = makeRequest(Self.host.appending(path: "api/v2/auth/jwk"), token: token)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["jwk": jwk])
        try await send(request)
    }

    /// A fresh Plex JWT, from a device JWT signing the nonce plex.tv issues.
    func renewToken(signing sign: @Sendable (String) throws -> String) async throws -> String {
        struct Nonce: Decodable { let nonce: String }
        struct Issued: Decodable { let auth_token: String }
        let nonce = try await decode(Nonce.self, from: makeRequest(Self.host.appending(path: "api/v2/auth/nonce"))).nonce
        var request = makeRequest(Self.host.appending(path: "api/v2/auth/token"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["jwt": try sign(nonce)])
        return try await decode(Issued.self, from: request).auth_token
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

    /// Avatars of people who share with the account, keyed by their numeric
    /// id (which matches `PlexResource.ownerId`). Uses the legacy XML
    /// `/api/users` endpoint, which only plex.tv itself serves;
    /// `/api/v2/friends` has been retired.
    func friendAvatars(token: String) async throws -> [Int: URL] {
        var request = makeRequest(URL(string: "https://plex.tv/api/users")!, token: token)
        request.setValue("application/xml", forHTTPHeaderField: "Accept")
        guard let root = XMLNodeParser.parse(try await send(request)) else { return [:] }
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
        try JSONDecoder().decode(type, from: try await send(request))
    }

    private func xml(from request: URLRequest) async throws -> Node {
        guard let root = XMLNodeParser.parse(try await send(request)) else { throw PlexTVError.unreadable }
        return root
    }

    @discardableResult
    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PlexTVError.nonHTTPResponse }
        guard (200..<300).contains(http.statusCode) else { throw PlexTVError.status(http.statusCode) }
        return data
    }
}
