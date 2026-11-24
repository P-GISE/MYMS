import Foundation
import Combine

private struct CloudUser: Decodable {
    struct Metadata: Decodable { let age_group: String? }

    let id: UUID
    let email: String?
    let user_metadata: Metadata?
}

private struct CloudSession: Decodable {
    let access_token: String
    let refresh_token: String
    let user: CloudUser
}

@MainActor
final class Accounts: ObservableObject {
    @Published private(set) var current: LocalAccount?
    @Published private(set) var busy = false
    @Published private(set) var restoring = false
    @Published var message: String?
    private var token: String?
    private var refreshToken: String?
    private var refreshing: Task<CloudSession, Error>?
    private var sessionRevision = UUID()
    private let vault: TokenVault
    private let preferences: UserDefaults
    static let restoreDisabledKey = "myms.session.restoreDisabled"

    static let localAccountID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    var isLocalMode: Bool { current?.id == Self.localAccountID }

    func enterLocalMode() {
        guard !busy, !restoring else { return }
        endSession()
        let age = UserDefaults.standard.string(forKey: "myms.local.ageGroup").flatMap(AgeGroup.init(rawValue:))
        current = LocalAccount(id: Self.localAccountID, email: "이 기기에 저장", ageGroup: age)
    }

    init(vault: TokenVault = MYMSCloud.refreshVault, preferences: UserDefaults = .standard) {
        self.vault = vault
        self.preferences = preferences
        if preferences.bool(forKey: Self.restoreDisabledKey) {
            do { try vault.remove() } catch { message = error.localizedDescription }
            return
        }
        do { refreshToken = try vault.read() }
        catch { message = error.localizedDescription; return }
        guard refreshToken != nil else { return }
        restoring = true
        Task {
            defer { restoring = false }
            do { try await loadAccount(refreshSession().user) }
            catch { if message == nil { message = error.localizedDescription } }
        }
    }

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

    /// 로그인한 계정으로 요청합니다. 토큰이 만료되어 401이 오면 한 번 갱신한 뒤 다시 보냅니다.
    func request(_ path: String, method: String = "GET", body: [String: Any]? = nil,
                 prefer: String? = nil) async throws -> Data {
        guard let token else { throw URLError(.userAuthenticationRequired) }
        let accountID = current?.id
        let revision = sessionRevision
        do {
            let data = try await MYMSCloud.request(path, method: method, token: token, body: body, prefer: prefer)
            guard sessionRevision == revision, current?.id == accountID else { throw URLError(.cancelled) }
            return data
        } catch let error as MYMSCloud.RequestError where error.status == 401 {
            guard sessionRevision == revision, current?.id == accountID else { throw URLError(.userAuthenticationRequired) }
            var fresh = self.token
            if fresh == token { fresh = try await refreshSession().access_token }
            guard sessionRevision == revision, current?.id == accountID, let fresh else { throw error }
            let data = try await MYMSCloud.request(path, method: method, token: fresh, body: body, prefer: prefer)
            guard sessionRevision == revision, current?.id == accountID else { throw URLError(.cancelled) }
            return data
        }
    }

    private func passwordSession(email: String, password: String) async throws -> CloudSession {
        let data = try await MYMSCloud.request("/auth/v1/token?grant_type=password", method: "POST", body: [
            "email": normalize(email), "password": password
        ])
        return try JSONDecoder().decode(CloudSession.self, from: data)
    }

    /// 동시에 여러 요청이 만료되어도 갱신은 한 번만 보냅니다. refresh token은 한 번 쓰면 바뀌기 때문입니다.
    private func refreshSession() async throws -> CloudSession {
        if let refreshing { return try await refreshing.value }
        guard let refreshToken else { throw URLError(.userAuthenticationRequired) }
        let revision = sessionRevision
        let task = Task<CloudSession, Error> {
            defer { if sessionRevision == revision { refreshing = nil } }
            do {
                let data = try await MYMSCloud.request("/auth/v1/token?grant_type=refresh_token", method: "POST",
                                                       body: ["refresh_token": refreshToken])
                let session = try JSONDecoder().decode(CloudSession.self, from: data)
                guard self.sessionRevision == revision, self.refreshToken == refreshToken else { throw URLError(.cancelled) }
                try adopt(session)
                return session
            } catch let error as MYMSCloud.RequestError where [400, 401, 403].contains(error.status) {
                if self.sessionRevision == revision, self.refreshToken == refreshToken {
                    endSession(message: "로그인이 만료되었습니다. 다시 로그인하세요.")
                }
                throw error
            }
        }
        refreshing = task
        return try await task.value
    }

    private func open(_ session: CloudSession) async throws {
        try adopt(session)
        try await loadAccount(session.user)
    }

    private func adopt(_ session: CloudSession) throws {
        try vault.write(session.refresh_token)
        preferences.set(false, forKey: Self.restoreDisabledKey)
        token = session.access_token
        refreshToken = session.refresh_token
    }

    private func endSession(message: String? = nil) {
        // Fail closed on the next launch even if Keychain deletion fails while the device locks.
        preferences.set(true, forKey: Self.restoreDisabledKey)
        sessionRevision = UUID()
        token = nil
        refreshToken = nil
        refreshing?.cancel()
        refreshing = nil
        current = nil
        self.message = message
        do { try vault.remove() }
        catch { self.message = "기기 로그인 정보 삭제에 실패했습니다: " + error.localizedDescription }
    }

    private func loadAccount(_ user: CloudUser) async throws {
        let revision = sessionRevision
        let data = try await request("/rest/v1/profiles?id=eq.\(user.id.uuidString)&select=age_group")
        let rows = try JSONDecoder().decode([Profile].self, from: data)
        let code = rows.first?.age_group ?? (rows.isEmpty ? user.user_metadata?.age_group : nil)
        if rows.isEmpty {
            _ = try await request("/rest/v1/profiles", method: "POST",
                                  body: ["id": user.id.uuidString, "age_group": code as Any? ?? NSNull()],
                                  prefer: "resolution=ignore-duplicates")
        }
        guard sessionRevision == revision else { throw URLError(.cancelled) }
        current = LocalAccount(id: user.id, email: user.email ?? "", ageGroup: AgeGroup.allCases.first { $0.cloudCode == code })
    }

    private struct Profile: Decodable { let age_group: String? }

    func updateAgeGroup(_ ageGroup: AgeGroup?) {
        guard var account = current else { return }
        if isLocalMode {
            account.ageGroup = ageGroup
            UserDefaults.standard.set(ageGroup?.rawValue, forKey: "myms.local.ageGroup")
            current = account
            return
        }
        authenticate {
            _ = try await self.request("/rest/v1/profiles?id=eq.\(account.id.uuidString)", method: "PATCH",
                                       body: ["age_group": ageGroup?.cloudCode as Any? ?? NSNull()])
            account.ageGroup = ageGroup
            self.current = account
        }
    }

    /// 서버 응답과 상관없이 기기에서는 바로 로그아웃합니다.
    func signOut() {
        guard !busy else { return }
        if isLocalMode { endSession(); return }
        guard let token else { return }
        endSession()
        Task { _ = try? await MYMSCloud.request("/auth/v1/logout?scope=local", method: "POST", token: token) }
    }

    func delete(password: String) async -> Bool {
        guard let account = current, !busy else { return false }
        guard !isLocalMode else {
            message = "로컬 모드에서는 기록 화면에서 기록을 삭제하세요."
            return false
        }
        busy = true
        defer { busy = false }
        do {
            let session = try await passwordSession(email: account.email, password: password)
            _ = try await MYMSCloud.request("/rest/v1/rpc/delete_my_account", method: "POST",
                                           token: session.access_token, body: [:])
            var cleanupError: String?
            do { try WorkoutStore.deleteLocalData(for: account.id) }
            catch {
                cleanupError = "서버 계정은 삭제됐지만 기기 기록 삭제에 실패했습니다: " + error.localizedDescription
            }
            let prefix = WorkoutStore.namespace(for: account.id)
            UserDefaults.standard.removeObject(forKey: prefix + "myms.plans")
            UserDefaults.standard.removeObject(forKey: prefix + "myms.records")
            endSession(message: cleanupError)
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
