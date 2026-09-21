import Foundation
import Security

enum TokenStore {
    private static let service = "mldgg.devtools"
    private static let account = "plex.tv"

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
        query[kSecMatchLimit] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
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
        insert[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw Failure.status(addStatus) }
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
