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

    static let refreshVault = TokenVault(service: "edu.myms.fitness.session", account: "refresh_token")

    static func isTrustedURL(_ candidate: URL?) -> Bool {
        guard let candidate, let base = URL(string: url), candidate.scheme?.lowercased() == "https",
              candidate.host?.lowercased() == base.host?.lowercased(), (candidate.port ?? 443) == 443,
              candidate.user == nil, candidate.password == nil, candidate.fragment == nil else { return false }
        return candidate.path.hasPrefix("/auth/v1/") || candidate.path.hasPrefix("/rest/v1/")
    }

    static func networkConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        return configuration
    }

    private static let session = URLSession(configuration: networkConfiguration(), delegate: RedirectGuard(), delegateQueue: nil)

    static func makeRequest(_ path: String, method: String = "GET", token: String? = nil,
                            body: [String: Any]? = nil, prefer: String? = nil) throws -> URLRequest {
        guard path.hasPrefix("/"), !path.hasPrefix("//"), !path.contains("\\"),
              !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let base = URL(string: url), let endpoint = URL(string: path, relativeTo: base)?.absoluteURL,
              isTrustedURL(endpoint) else { throw URLError(.badURL) }
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = method
        request.setValue(key, forHTTPHeaderField: "apikey")
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    static func request(_ path: String, method: String = "GET", token: String? = nil,
                        body: [String: Any]? = nil, prefer: String? = nil) async throws -> Data {
        let request = try makeRequest(path, method: method, token: token, body: body, prefer: prefer)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let detail = payload?["msg"] as? String ?? payload?["message"] as? String ?? "Supabase 요청 실패"
            throw RequestError(status: http.statusCode, detail: detail)
        }
        return data
    }

    private final class RedirectGuard: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(isTrustedURL(request.url) ? request : nil)
        }
    }
}
