import Foundation
import Security

protocol APIKeyStoring {
    func apiKey(for backendId: String) -> String?
    func setAPIKey(_ key: String?, for backendId: String) throws
}

enum KeychainError: LocalizedError {
    case status(OSStatus)

    var errorDescription: String? {
        switch self {
        case .status(let status):
            return "Keychain error \(status)"
        }
    }
}

/// Stores backend API keys in the app's own keychain items.
/// The app never reads or writes anything outside service `com.ernest.clipshot`.
final class KeychainStore: APIKeyStoring {
    let service: String

    init(service: String = "com.ernest.clipshot") {
        self.service = service
    }

    func apiKey(for backendId: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "\(backendId).api-key",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return nil }
        return value
    }

    func setAPIKey(_ key: String?, for backendId: String) throws {
        let account = "\(backendId).api-key"
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        guard let key, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            SecItemDelete(baseQuery as CFDictionary)
            return
        }

        let data = Data(key.utf8)
        let updateAttributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, updateAttributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.status(addStatus) }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.status(updateStatus)
        }
    }
}
