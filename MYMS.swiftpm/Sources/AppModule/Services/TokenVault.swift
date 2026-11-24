import Foundation
import Security

struct TokenVault {
    let service: String
    let account: String

    struct VaultError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "기기 보안 저장소 오류 (\(status))" }
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account, kSecAttrSynchronizable as String: false]
    }

    func read() throws -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw VaultError(status: status) }
        guard let data = item as? Data, let token = String(data: data, encoding: .utf8), !token.isEmpty else {
            throw VaultError(status: errSecDecode)
        }
        return token
    }

    func write(_ token: String) throws {
        guard !token.isEmpty else { throw VaultError(status: errSecParam) }
        let values: [String: Any] = [kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        // Update first: a failed write must not delete the previously saved credential.
        var status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(values) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw VaultError(status: status) }
    }

    func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw VaultError(status: status) }
    }
}
