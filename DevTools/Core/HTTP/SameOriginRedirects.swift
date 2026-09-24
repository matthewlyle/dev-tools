import Foundation

final class SameOriginRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    static func allows(from source: URL, to target: URL) -> Bool {
        guard let scheme = source.scheme?.lowercased(), scheme == target.scheme?.lowercased(),
              let host = source.host()?.lowercased(), host == target.host()?.lowercased()
        else { return false }
        return effectivePort(source) == effectivePort(target)
    }

    private static func effectivePort(_ url: URL) -> Int? {
        if let port = url.port { return port }
        switch url.scheme?.lowercased() {
        case "https", "wss": return 443
        case "http", "ws": return 80
        default: return nil
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        guard let source = response.url, let target = request.url, Self.allows(from: source, to: target) else { return nil }
        return request
    }
}
