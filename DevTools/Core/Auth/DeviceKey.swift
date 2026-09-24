import CryptoKit
import Foundation

/// This install's Ed25519 key, which plex.tv holds the public half of: it
/// signs the device JWTs that exchange an approved PIN for a Plex token and
/// renew that token before its 7 days run out. The private half never leaves
/// the Keychain.
struct DeviceKey: Sendable {
    let privateKey: Curve25519.Signing.PrivateKey

    /// The public key as a base64url JWK `x`.
    var x: String { Base64URL.encode(privateKey.publicKey.rawRepresentation) }

    /// The RFC 7638 thumbprint of the public JWK, so the id follows the key.
    var keyID: String {
        let canonical = #"{"crv":"Ed25519","kty":"OKP","x":"\#(x)"}"#
        return Base64URL.encode(Data(SHA256.hash(data: Data(canonical.utf8))))
    }

    var jwk: [String: String] {
        ["kty": "OKP", "crv": "Ed25519", "x": x, "kid": keyID, "use": "sig", "alg": "EdDSA"]
    }

    static func loadOrCreate() throws -> DeviceKey {
        if let raw = TokenStore.loadDeviceKey() {
            return DeviceKey(privateKey: try Curve25519.Signing.PrivateKey(rawRepresentation: raw))
        }
        let key = Curve25519.Signing.PrivateKey()
        try TokenStore.saveDeviceKey(key.rawRepresentation)
        return DeviceKey(privateKey: key)
    }

    /// A short-lived JWT plex.tv verifies against the registered key. A PIN
    /// exchange needs no nonce; a renewal signs the nonce plex.tv just issued.
    func deviceJWT(clientIdentifier: String, nonce: String? = nil, scope: String? = nil, now: Date = .now) throws -> String {
        let issued = Int(now.timeIntervalSince1970)
        var claims: [String: Any] = ["aud": "plex.tv", "iss": clientIdentifier, "iat": issued, "exp": issued + 300]
        if let nonce { claims["nonce"] = nonce }
        if let scope { claims["scope"] = scope }
        let header: [String: Any] = ["kid": keyID, "alg": "EdDSA", "typ": "JWT"]
        let signingInput = try Self.segment(header) + "." + Self.segment(claims)
        let signature = try privateKey.signature(for: Data(signingInput.utf8))
        return signingInput + "." + Base64URL.encode(signature)
    }

    private static func segment(_ object: [String: Any]) throws -> String {
        Base64URL.encode(try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
    }
}

/// What the app reads from a Plex token without verifying it: whether it's a
/// JWT at all (legacy tokens aren't), and when it expires.
enum PlexToken {
    static func isJWT(_ token: String) -> Bool {
        token.split(separator: ".", omittingEmptySubsequences: false).count == 3
    }

    static func expiry(of token: String) -> Date? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let payload = Base64URL.decode(String(parts[1])),
              let claims = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let exp = claims["exp"] as? NSNumber
        else { return nil }
        return Date(timeIntervalSince1970: exp.doubleValue)
    }
}

enum Base64URL {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ string: String) -> Data? {
        var base64 = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }
}
