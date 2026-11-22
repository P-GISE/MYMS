import Foundation

enum MYMSCloud {
    static let url = "https://jlqustzqllvkeokjnjiw.supabase.co"
    static let key = "sb_publishable_SCbQKG6cvQi-UBqAGwhX0Q_EXekm8LK"

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
}
