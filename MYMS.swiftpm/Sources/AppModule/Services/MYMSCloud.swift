import Foundation
import Security

enum MYMSCloud {
    static let url = "https://pppidannfctewwtshspw.supabase.co"
    static let key = "sb_publishable_tuvdGsU8Op-RPmaceKhxFQ_fLRxLpkw"

    struct RequestError: LocalizedError {
        let status: Int
        let detail: String
        var errorDescription: String? { detail }
    }

    static func request(_ path: String, method: String = "GET", token: String? = nil,
                        body: [String: Any]? = nil, prefer: String? = nil) async throws -> Data {
        var request = URLRequest(url: URL(string: url + path)!)
        request.httpMethod = method
        request.setValue(key, forHTTPHeaderField: "apikey")
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let detail = payload?["msg"] as? String ?? payload?["message"] as? String ?? "Supabase 요청 실패"
            throw RequestError(status: http.statusCode, detail: detail)
        }
        return data
    }

    private static let vault: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "edu.myms.fitness.session",
        kSecAttrAccount as String: "refresh_token"
    ]

    /// 앱을 다시 열어도 로그인이 유지되도록 Keychain에 보관하는 refresh token입니다.
    static var savedRefreshToken: String? {
        get {
            var query = vault
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data else { return nil }
            return String(decoding: data, as: UTF8.self)
        }
        set {
            SecItemDelete(vault as CFDictionary)
            guard let newValue else { return }
            var item = vault
            item[kSecValueData as String] = Data(newValue.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(item as CFDictionary, nil)
        }
    }
}
