import Foundation
import Security

/// On the Mac the item lives in the file-based keychain, where `accessibility` doesn't apply.
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
        ]
    }

    static func load() -> String? {
        var query = baseQuery
        query[kSecReturnData] = true
        query[kSecReturnAttributes] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
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
        let status = SecItemDelete(baseQuery as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
