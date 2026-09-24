import CryptoKit
import Foundation
import Testing
@testable import DevTools

struct DeviceKeyTests {
    /// RFC 8037 appendix A.1's Ed25519 key.
    private func rfcKey() throws -> DeviceKey {
        let d = try #require(Base64URL.decode("nWGxne_9WmC6hEr0kuwsxERJxWl7MmkZcDusAxyuf2A"))
        return DeviceKey(privateKey: try Curve25519.Signing.PrivateKey(rawRepresentation: d))
    }

    private func json(_ segment: Substring) throws -> [String: Any] {
        let data = try #require(Base64URL.decode(String(segment)))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func publicJWKAndKeyIDMatchRFC8037() throws {
        let key = try rfcKey()
        #expect(key.x == "11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo")
        #expect(key.keyID == "kPrK_qmxVWaYVA9wwBF6Iuo3vVzz7TxHCTwXBygrS4k")
        #expect(key.jwk["kty"] == "OKP")
        #expect(key.jwk["crv"] == "Ed25519")
        #expect(key.jwk["alg"] == "EdDSA")
        #expect(key.jwk["kid"] == key.keyID)
    }

    @Test func deviceJWTCarriesPlexClaimsAndVerifies() throws {
        let key = try rfcKey()
        let now = Date(timeIntervalSince1970: 1_705_785_603)
        let token = try key.deviceJWT(clientIdentifier: "client-1", nonce: "n-1", scope: "username,email", now: now)
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        try #require(parts.count == 3)

        let header = try json(parts[0])
        #expect(header["alg"] as? String == "EdDSA")
        #expect(header["kid"] as? String == key.keyID)
        #expect(header["typ"] as? String == "JWT")

        let claims = try json(parts[1])
        #expect(claims["aud"] as? String == "plex.tv")
        #expect(claims["iss"] as? String == "client-1")
        #expect(claims["nonce"] as? String == "n-1")
        #expect(claims["scope"] as? String == "username,email")
        #expect(claims["iat"] as? Int == 1_705_785_603)
        #expect(claims["exp"] as? Int == 1_705_785_903)

        let signature = try #require(Base64URL.decode(String(parts[2])))
        #expect(key.privateKey.publicKey.isValidSignature(signature, for: Data("\(parts[0]).\(parts[1])".utf8)))
    }

    @Test func pinExchangeJWTOmitsNonceAndScope() throws {
        let token = try rfcKey().deviceJWT(clientIdentifier: "client-1")
        let claims = try json(token.split(separator: ".")[1])
        #expect(claims["nonce"] == nil)
        #expect(claims["scope"] == nil)
    }

    @Test func plexTokenExpiryAndKind() throws {
        let payload = Base64URL.encode(try JSONSerialization.data(withJSONObject: ["exp": 1_800_000_000]))
        let jwt = "eyJhbGciOiJFZERTQSJ9.\(payload).c2ln"
        #expect(PlexToken.isJWT(jwt))
        #expect(PlexToken.expiry(of: jwt) == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(!PlexToken.isJWT("abcDEF123legacy"))
        #expect(PlexToken.expiry(of: "abcDEF123legacy") == nil)
    }
}
