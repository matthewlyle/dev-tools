import Foundation
import Security

enum TokenStore {
    private static let service = "mldgg.devtools"
    private static let account = "plex.tv"
    private static var accessibility: CFString { kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly }

    enum Failure: Error {
        case status(OSStatus)
    }

    private static var baseQuery: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecUseDataProtectionKeychain: true,
        ]
    }

    static func load() -> String? {
        var query = baseQuery
        query[kSecReturnData] = true
        query[kSecReturnAttributes] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        #if os(macOS)
        if status == errSecItemNotFound { return moveFromFileKeychain() }
        #endif
        guard status == errSecSuccess,
              let attributes = item as? [CFString: Any],
              let data = attributes[kSecValueData] as? Data
        else { return nil }
        #if os(iOS)
        // Items saved before ThisDeviceOnly can ride a backup onto another device.
        if let current = attributes[kSecAttrAccessible] as? String, current != accessibility as String {
            SecItemUpdate(baseQuery as CFDictionary, [kSecAttrAccessible: accessibility] as CFDictionary)
        }
        #endif
        return String(decoding: data, as: UTF8.self)
    }

    static func save(_ token: String) throws {
        let data = Data(token.utf8)
        let update: [CFString: Any] = [kSecValueData: data]
        let status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw Failure.status(status) }

        var insert = baseQuery
        insert[kSecValueData] = data
        insert[kSecAttrAccessible] = accessibility
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw Failure.status(addStatus) }
    }

    @discardableResult
    static func delete() -> Bool {
        #if os(macOS)
        let fileItemGone = remove(fileKeychainQuery)
        return remove(baseQuery) && fileItemGone
        #else
        return remove(baseQuery)
        #endif
    }

    private static func remove(_ query: [CFString: Any]) -> Bool {
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    #if os(macOS)
    private static var fileKeychainQuery: [CFString: Any] {
        var query = baseQuery
        query[kSecUseDataProtectionKeychain] = false
        return query
    }

    private static func moveFromFileKeychain() -> String? {
        var query = fileKeychainQuery
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        let token = String(decoding: data, as: UTF8.self)
        if (try? save(token)) != nil {
            _ = remove(fileKeychainQuery)
        }
        return token
    }
    #endif
}
