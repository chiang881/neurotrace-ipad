import Foundation
import Security

nonisolated enum SecureAPIKeyStore {
    private static let service = "top.hadal.NT-UI.large-model"
    private static let account = "api-key"

    static func load() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return ""
        }
        return value
    }

    static func save(_ value: String) throws {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            let status = SecItemDelete(baseQuery as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw SecureStoreError.status(status)
            }
            return
        }

        let data = Data(normalized.utf8)
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw SecureStoreError.status(updateStatus)
        }
        var insert = baseQuery
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let insertStatus = SecItemAdd(insert as CFDictionary, nil)
        guard insertStatus == errSecSuccess else {
            throw SecureStoreError.status(insertStatus)
        }
    }
}

nonisolated enum SecureStoreError: LocalizedError {
    case status(OSStatus)

    var errorDescription: String? {
        switch self {
        case .status(let status):
            return "无法保存安全配置（\(status)）。"
        }
    }
}
