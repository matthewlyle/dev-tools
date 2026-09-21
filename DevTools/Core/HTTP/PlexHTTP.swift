import Foundation

enum PlexHTTPError: Error, LocalizedError {
    case invalidURL
    case nonHTTPResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL: "The path and parameters don't form a valid URL."
        case .nonHTTPResponse: "The server returned a non-HTTP response."
        }
    }
}

/// Sends `PlexRequest`s. No caching: a dev tool must show what the server
/// actually returned right now. Non-2xx is a response, not an error.
final class PlexHTTP: Sendable {
    private let session: URLSession
    let identity: ClientIdentity

    init(identity: ClientIdentity) {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = 30
        config.httpAdditionalHeaders = nil
        self.session = URLSession(configuration: config)
        self.identity = identity
    }

    func send(_ request: PlexRequest, to server: ConnectedServer) async throws -> PlexResponse {
        try await send(request, baseURL: server.baseURL, token: server.accessToken)
    }

    func send(
        _ request: PlexRequest,
        baseURL: URL,
        token: String?,
        timeout: TimeInterval = 30
    ) async throws -> PlexResponse {
        guard let url = request.url(base: baseURL, token: token) else { throw PlexHTTPError.invalidURL }

        var urlRequest = URLRequest(url: url, timeoutInterval: timeout)
        urlRequest.httpMethod = "GET"
        urlRequest.setValue(request.accept.rawValue, forHTTPHeaderField: "Accept")
        for (name, value) in identity.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        if request.tokenPlacement == .header, let token {
            urlRequest.setValue(token, forHTTPHeaderField: "X-Plex-Token")
        }
        for header in request.headers where header.enabled {
            urlRequest.setValue(header.value, forHTTPHeaderField: header.name)
        }

        let clock = ContinuousClock()
        let start = clock.now
        let (data, response) = try await session.data(for: urlRequest)
        let duration = clock.now - start

        guard let http = response as? HTTPURLResponse else { throw PlexHTTPError.nonHTTPResponse }

        var headers: [String: String] = [:]
        headers.reserveCapacity(http.allHeaderFields.count)
        for (key, value) in http.allHeaderFields {
            headers["\(key)"] = "\(value)"
        }

        return PlexResponse(
            url: url,
            status: http.statusCode,
            headers: headers,
            body: data,
            duration: duration,
            receivedAt: .now
        )
    }
}
