import Foundation
import Combine

private struct CloudUser: Decodable {
    let id: UUID
    let email: String?
    let user_metadata: [String: String]?

    enum CodingKeys: String, CodingKey { case id, email, user_metadata }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        email = try values.decodeIfPresent(String.self, forKey: .email)
        user_metadata = try? values.decode([String: String].self, forKey: .user_metadata)
    }
}

private struct CloudSession: Decodable {
    let access_token: String
    let user: CloudUser
}

@MainActor
final class Accounts: ObservableObject {
    @Published private(set) var current: LocalAccount?
    @Published private(set) var busy = false
    @Published var message: String?
    private(set) var token: String?

    func register(email: String, password: String, ageGroup: AgeGroup) {
        authenticate {
            let data = try await MYMSCloud.request("/auth/v1/signup", method: "POST", body: [
                "email": self.normalize(email), "password": password, "data": ["age_group": ageGroup.cloudCode]
            ])
            guard let session = try? JSONDecoder().decode(CloudSession.self, from: data) else {
                self.message = "인증 메일에서 주소를 확인한 뒤 로그인하세요."
                return
            }
            try await self.open(session)
        }
    }

    func signIn(email: String, password: String) {
        authenticate { try await self.open(self.passwordSession(email: email, password: password)) }
    }

    private func passwordSession(email: String, password: String) async throws -> CloudSession {
        let data = try await MYMSCloud.request("/auth/v1/token?grant_type=password", method: "POST", body: [
            "email": normalize(email), "password": password
        ])
        return try JSONDecoder().decode(CloudSession.self, from: data)
    }

    private func open(_ session: CloudSession) async throws {
        let id = session.user.id
        let data = try await MYMSCloud.request("/rest/v1/profiles?id=eq.\(id.uuidString)&select=age_group", token: session.access_token)
        let rows = try JSONDecoder().decode([Profile].self, from: data)
        let code = rows.first?.age_group ?? (rows.isEmpty ? session.user.user_metadata?["age_group"] : nil)
        if rows.isEmpty {
            _ = try await MYMSCloud.request("/rest/v1/profiles", method: "POST", token: session.access_token,
                                           body: ["id": id.uuidString, "age_group": code as Any? ?? NSNull()],
                                           prefer: "resolution=ignore-duplicates")
        }
        token = session.access_token
        current = LocalAccount(id: id, email: session.user.email ?? "", ageGroup: AgeGroup.allCases.first { $0.cloudCode == code })
    }

    private struct Profile: Decodable { let age_group: String? }

    func updateAgeGroup(_ ageGroup: AgeGroup?) {
        guard var account = current, let token else { return }
        authenticate {
            _ = try await MYMSCloud.request("/rest/v1/profiles?id=eq.\(account.id.uuidString)", method: "PATCH",
                                           token: token, body: ["age_group": ageGroup?.cloudCode as Any? ?? NSNull()])
            account.ageGroup = ageGroup
            self.current = account
        }
    }

    func signOut() {
        guard let token else { return }
        authenticate {
            _ = try await MYMSCloud.request("/auth/v1/logout?scope=local", method: "POST", token: token)
            self.token = nil
            self.current = nil
        }
    }

    func delete(password: String) async -> Bool {
        guard let account = current, !busy else { return false }
        busy = true
        defer { busy = false }
        do {
            let session = try await passwordSession(email: account.email, password: password)
            _ = try await MYMSCloud.request("/rest/v1/rpc/delete_my_account", method: "POST",
                                           token: session.access_token, body: [:])
            let prefix = WorkoutStore.namespace(for: account.id)
            UserDefaults.standard.removeObject(forKey: prefix + "myms.plans")
            UserDefaults.standard.removeObject(forKey: prefix + "myms.records")
            token = nil
            current = nil
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    private func authenticate(_ operation: @escaping () async throws -> Void) {
        guard !busy else { return }
        busy = true
        message = nil
        Task {
            defer { busy = false }
            do { try await operation() }
            catch { message = error.localizedDescription }
        }
    }

    private func normalize(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
