import Foundation
import Security

/// The Plex token and this install's device key, in the Keychain.
enum TokenStore {
    private static let service = "mldgg.devtools"
    private static let tokenAccount = "plex.tv"
    private static let deviceKeyAccount = "plex.tv.device-key"

    enum Failure: Error {
        case status(OSStatus)
    }

    static func load() -> String? {
        data(for: tokenAccount).map { String(decoding: $0, as: UTF8.self) }
    }

    static func save(_ token: String) throws {
        try save(Data(token.utf8), for: tokenAccount)
    }

    static func delete() {
        SecItemDelete(query(for: tokenAccount) as CFDictionary)
    }

    /// Kept across sign-outs: plex.tv already holds its public half, so the
    /// next sign-in reuses the registration.
    static func loadDeviceKey() -> Data? {
        data(for: deviceKeyAccount)
    }

    static func saveDeviceKey(_ raw: Data) throws {
        try save(raw, for: deviceKeyAccount)
    }

    private static func query(for account: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
    }

    private static func data(for account: String) -> Data? {
        var query = query(for: account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    private static func save(_ data: Data, for account: String) throws {
        let update: [CFString: Any] = [kSecValueData: data]
        let status = SecItemUpdate(query(for: account) as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw Failure.status(status) }

        var insert = query(for: account)
        insert[kSecValueData] = data
        insert[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw Failure.status(addStatus) }
    }
}
