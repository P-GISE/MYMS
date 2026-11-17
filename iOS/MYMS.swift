import CoreBluetooth
import SwiftUI

enum Exercise: String, Codable, CaseIterable {
    case pushup = "푸시업", squat = "스쿼트"
    case bridge = "힙 브리지", kneeRaise = "앉아서 무릎 들기"

    var cloudCode: String {
        switch self {
        case .pushup: "pushup"
        case .squat: "squat"
        case .bridge: "bridge"
        case .kneeRaise: "knee-raise"
        }
    }

    var symbol: String {
        switch self {
        case .pushup: "figure.strengthtraining.traditional"
        case .squat: "figure.strengthtraining.functional"
        case .bridge: "figure.cooldown"
        case .kneeRaise: "figure.core.training"
        }
    }

    var returnDepth: Double { self == .pushup ? 0.15 : 0.10 }

    func depth(for level: Level) -> Double {
        let thresholds: [Double]
        switch self {
        case .pushup: thresholds = [0.35, 0.50, 0.65]
        case .squat: thresholds = [0.20, 0.30, 0.45]
        case .bridge, .kneeRaise: thresholds = [0.15, 0.25, 0.35]
        }
        return thresholds[level.rawValue - 1]
    }

    var placement: String {
        switch self {
        case .pushup: "센서를 가슴 바로 아래 바닥에 놓고 위를 향하게 하세요."
        case .squat: "센서를 엉덩이 바로 아래 바닥에 놓고 위를 향하게 하세요. 발이나 다리가 센서 앞을 가리지 않게 위치를 맞추세요."
        case .bridge: "센서를 고정 거치대에 달아 골반 바로 위에서 아래를 향하게 하세요. 골반을 들어 올렸을 때 센서와 닿지 않을 만큼 공간을 확보하세요."
        case .kneeRaise: "센서를 고정 거치대에 달아 들어 올릴 다리의 무릎 가까운 허벅지 위에서 아래를 향하게 하세요. 세트마다 한쪽 다리만 측정하고, 반대쪽은 센서 위치를 옮긴 뒤 새 세트에서 진행하세요."
        }
    }

    var measurementNote: String? {
        switch self {
        case .pushup: nil
        case .squat: "스쿼트는 센서와 몸 사이가 멀어 거리 측정이 끊길 수 있어 실측이 필요합니다."
        case .bridge, .kneeRaise: "난이도별 기준은 초기값입니다. 거치 높이에 따라 같은 동작의 거리 변화 비율이 달라지므로 설치 후 실측이 필요합니다."
        }
    }

    var steps: [String] {
        switch self {
        case .pushup: [
            "손을 어깨너비 정도로 짚고 팔을 펴세요. 무릎을 바닥에 대고 시작해도 됩니다.",
            "팔꿈치를 굽혀 가슴을 센서 쪽으로 내리세요.",
            "바닥을 밀어 가슴을 처음 높이로 되돌리세요."
        ]
        case .squat: [
            "발을 어깨너비 정도로 벌리고 엉덩이가 센서 위에 오도록 서세요.",
            "엉덩이를 뒤로 보내며 무릎을 굽히세요. 무릎은 발끝 방향을 향하게 하세요.",
            "발바닥으로 바닥을 밀며 처음 선 자세로 돌아오세요."
        ]
        case .bridge: [
            "등을 대고 누워 무릎을 굽히고 발바닥을 바닥에 붙이세요.",
            "발바닥으로 바닥을 누르며 골반을 센서 쪽으로 들어 올리세요.",
            "골반을 천천히 내려 처음 자세로 돌아오세요."
        ]
        case .kneeRaise: [
            "흔들리지 않는 의자에 앉아 두 발을 바닥에 두세요.",
            "몸통을 고정하고 한쪽 무릎을 굽힌 채 허벅지를 센서 쪽으로 들어 올리세요.",
            "발을 천천히 바닥으로 내려 처음 자세로 돌아오세요."
        ]
        }
    }
}

enum Level: Int, Codable, CaseIterable {
    case easy = 1, normal, deep
    var title: String { ["초급", "중급", "상급"][rawValue - 1] }
}

struct Workout: Codable, Identifiable, Equatable {
    var id = UUID()
    var exercise = Exercise.pushup
    var level = Level.normal
    var target = 10
    var sets = 3
    var rest = 30

    var cloudFields: [String: Any] {
        ["exercise_slug": exercise.cloudCode, "level": level.rawValue, "target_reps": target,
         "target_sets": sets, "rest_seconds": rest]
    }
}

struct WorkoutRecord: Codable, Identifiable {
    var id = UUID()
    var workout: Workout
    var date = Date()
    var reps: Int
    var sets: Int
    var seconds: Int
    var note = ""
    var points: Int
}

@MainActor
final class WorkoutStore: ObservableObject {
    @Published var plans: [Workout] = [] {
        didSet { if loaded && !loading { queuePlanChanges(from: oldValue) } }
    }
    @Published var records: [WorkoutRecord] = [] {
        didSet { if loaded && !loading { queueRecordChanges(from: oldValue) } }
    }
    @Published private(set) var loaded = false
    @Published private(set) var syncError: String?
    @Published private(set) var syncing = false

    private let token: String?
    private var loading = false
    private var pending: [Mutation] = []

    private struct Mutation {
        let path: String
        let method: String
        let body: [String: Any]?
        var prefer: String? = nil
    }

    var points: Int { records.reduce(0) { $0 + $1.points } }

    init(token: String?) { self.token = token }

    static func namespace(for accountID: UUID) -> String {
        "myms.account.\(accountID.uuidString)."
    }

    func load() async {
        guard !loaded, !loading, let token else { return }
        loading = true
        syncError = nil
        defer { loading = false }
        do {
            async let planData = MYMSCloud.request("/rest/v1/workout_plans?order=sort_order.asc,id.asc", token: token)
            async let sessionData = MYMSCloud.request("/rest/v1/workout_sessions?order=finished_at.desc,id.desc", token: token)
            let decoder = JSONDecoder()
            let plans = try decoder.decode([PlanRow].self, from: await planData).map { try $0.workout() }
            let records = try decoder.decode([SessionRow].self, from: await sessionData).map { try $0.record() }
            self.plans = plans
            self.records = records
            loaded = true
        } catch {
            syncError = error.localizedDescription
        }
    }

    func retry() {
        if loaded { flush() }
        else { Task { await load() } }
    }

    private func flush() {
        guard !syncing, !pending.isEmpty, let token else { return }
        syncing = true
        syncError = nil
        Task {
            defer { syncing = false }
            while let next = pending.first {
                do {
                    _ = try await MYMSCloud.request(next.path, method: next.method, token: token,
                                                    body: next.body, prefer: next.prefer)
                    pending.removeFirst()
                } catch {
                    syncError = error.localizedDescription
                    return
                }
            }
        }
    }

    private func queuePlanChanges(from previous: [Workout]) {
        let oldByID = Dictionary(uniqueKeysWithValues: previous.enumerated().map { ($0.element.id, $0.offset) })
        for old in previous where !plans.contains(where: { $0.id == old.id }) {
            pending.append(Mutation(path: "/rest/v1/workout_plans?id=eq.\(old.id.uuidString)", method: "DELETE", body: nil))
        }
        for (index, plan) in plans.enumerated() {
            if let oldIndex = oldByID[plan.id], oldIndex == index, previous[oldIndex] == plan { continue }
            var fields = plan.cloudFields
            fields["id"] = plan.id.uuidString
            fields["sort_order"] = index
            pending.append(Mutation(path: "/rest/v1/workout_plans", method: "POST", body: fields,
                                    prefer: "resolution=merge-duplicates"))
        }
        flush()
    }

    private func queueRecordChanges(from previous: [WorkoutRecord]) {
        let oldByID = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
        for old in previous where !records.contains(where: { $0.id == old.id }) {
            pending.append(Mutation(path: "/rest/v1/workout_sessions?id=eq.\(old.id.uuidString)", method: "DELETE", body: nil))
        }
        for record in records {
            if let old = oldByID[record.id] {
                if old.note != record.note {
                    pending.append(Mutation(path: "/rest/v1/workout_sessions?id=eq.\(record.id.uuidString)",
                                            method: "PATCH", body: ["note": record.note]))
                }
            } else {
                var fields = record.workout.cloudFields
                fields["id"] = record.id.uuidString
                fields["valid_reps"] = record.reps
                fields["completed_sets"] = record.sets
                fields["duration_seconds"] = record.seconds
                fields["finished_at"] = ISO8601DateFormatter().string(from: record.date)
                fields["note"] = record.note
                fields["points_earned"] = record.points
                pending.append(Mutation(path: "/rest/v1/workout_sessions", method: "POST", body: fields,
                                        prefer: "resolution=ignore-duplicates"))
            }
        }
        flush()
    }

    func save(_ record: WorkoutRecord) {
        guard loaded, !records.contains(where: { $0.id == record.id }) else { return }
        var entry = record
        let today = records.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.points }
        entry.points = min(entry.points, max(0, 300 - today))
        records.insert(entry, at: 0)
    }

    private struct PlanRow: Decodable {
        let id: UUID
        let exercise_slug: String
        let level: Int
        let target_reps: Int
        let target_sets: Int
        let rest_seconds: Int

        func workout() throws -> Workout {
            guard let exercise = Exercise.allCases.first(where: { $0.cloudCode == exercise_slug }),
                  let level = Level(rawValue: level) else { throw URLError(.cannotDecodeContentData) }
            return Workout(id: id, exercise: exercise, level: level, target: target_reps,
                           sets: target_sets, rest: rest_seconds)
        }
    }

    private struct SessionRow: Decodable {
        let plan: PlanRow
        let finished_at: String
        let valid_reps: Int
        let completed_sets: Int
        let duration_seconds: Int
        let note: String
        let points_earned: Int

        enum CodingKeys: String, CodingKey {
            case finished_at, valid_reps, completed_sets, duration_seconds, note, points_earned
        }

        init(from decoder: Decoder) throws {
            plan = try PlanRow(from: decoder)
            let row = try decoder.container(keyedBy: CodingKeys.self)
            finished_at = try row.decode(String.self, forKey: .finished_at)
            valid_reps = try row.decode(Int.self, forKey: .valid_reps)
            completed_sets = try row.decode(Int.self, forKey: .completed_sets)
            duration_seconds = try row.decode(Int.self, forKey: .duration_seconds)
            note = try row.decode(String.self, forKey: .note)
            points_earned = try row.decode(Int.self, forKey: .points_earned)
        }

        func record() throws -> WorkoutRecord {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions.insert(.withFractionalSeconds)
            var date = formatter.date(from: finished_at)
            if date == nil {
                formatter.formatOptions.remove(.withFractionalSeconds)
                date = formatter.date(from: finished_at)
            }
            guard let date else { throw URLError(.cannotDecodeContentData) }
            return WorkoutRecord(id: plan.id, workout: try plan.workout(), date: date, reps: valid_reps,
                                 sets: completed_sets, seconds: duration_seconds, note: note, points: points_earned)
        }
    }
}

enum AgeGroup: String, Codable, CaseIterable {
    case teens = "10대", twenties = "20대", thirties = "30대", forties = "40대"
    case fifties = "50대", sixties = "60대", older = "70대 이상"

    var cloudCode: String {
        switch self {
        case .teens: "teens"
        case .twenties: "twenties"
        case .thirties: "thirties"
        case .forties: "forties"
        case .fifties: "fifties"
        case .sixties: "sixties"
        case .older: "older"
        }
    }

    var volumeAdjustment: Int {
        switch self {
        case .twenties, .thirties, .forties: 0
        case .teens, .fifties: 1
        case .sixties, .older: 2
        }
    }
}

struct LocalAccount: Codable {
    let id: UUID
    let email: String
    var ageGroup: AgeGroup?
}

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

private enum MYMSCloud {
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

struct LoginScreen: View {
    @ObservedObject var accounts: Accounts
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            AccountPage(title: "로그인", subtitle: "MYMS 운동 계획과 기록을 이어서 확인하세요.") {
                AccountEmailField(email: $email)
                    .submitLabel(.next)
                AccountField(title: "비밀번호") {
                    SecureField("비밀번호 입력", text: $password)
                        .accessibilityLabel("비밀번호")
                        .textContentType(.password)
                        .submitLabel(.go)
                        .onSubmit(signIn)
                }
                if let message = accounts.message {
                    Text(message).font(.footnote).foregroundStyle(.red)
                }
                Button(action: signIn) {
                    Text("로그인").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(accounts.busy || email.isEmpty || password.isEmpty)

                HStack(spacing: 6) {
                    Text("처음 이용하시나요?").foregroundStyle(.secondary)
                    NavigationLink("회원가입") { RegistrationScreen(accounts: accounts) }
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            }
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { accounts.message = nil }
        }
    }

    private func signIn() {
        guard !accounts.busy, !email.isEmpty, !password.isEmpty else { return }
        accounts.signIn(email: email, password: password)
    }
}

struct RegistrationScreen: View {
    @ObservedObject var accounts: Accounts
    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var ageGroup: AgeGroup?

    private var passwordsDiffer: Bool {
        !confirmation.isEmpty && confirmation != password
    }

    var body: some View {
        AccountPage(title: "회원가입", subtitle: "계정을 만들고 운동 추천에 사용할 연령대를 선택하세요.") {
            AccountEmailField(email: $email)
            AccountField(title: "비밀번호") {
                SecureField("8자 이상", text: $password)
                    .accessibilityLabel("비밀번호")
                    .textContentType(.newPassword)
            }
            AccountField(title: "비밀번호 확인") {
                SecureField("비밀번호 다시 입력", text: $confirmation)
                    .accessibilityLabel("비밀번호 확인")
                    .textContentType(.newPassword)
            }
            AccountField(title: "연령대") {
                AgeGroupPicker(selection: $ageGroup)
                    .labelsHidden()
                    .pickerStyle(.menu)
            }
            if passwordsDiffer {
                Text("비밀번호가 일치하지 않습니다.").font(.footnote).foregroundStyle(.red)
            } else if let message = accounts.message {
                Text(message).font(.footnote).foregroundStyle(.red)
            }
            Button {
                guard let ageGroup, password == confirmation else { return }
                accounts.register(email: email, password: password, ageGroup: ageGroup)
            } label: {
                Text("계정 만들기").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(accounts.busy || email.isEmpty || password.count < 8 || password != confirmation || ageGroup == nil)

            Text("계정과 운동 데이터는 Supabase에 저장됩니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { accounts.message = nil }
    }
}

private struct AccountEmailField: View {
    @Binding var email: String

    var body: some View {
        AccountField(title: "이메일") {
            TextField("name@example.com", text: $email)
                .accessibilityLabel("이메일")
                .keyboardType(.emailAddress)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }
}

private struct AccountField<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.subheadline.weight(.semibold)).accessibilityHidden(true)
            content
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .background(Color(uiColor: .systemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

private struct AccountPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 850 && !typeSize.isAccessibilitySize
            let inset: CGFloat = wide ? 32 : 20
            let contentWidth = min(wide ? 940 : 480, max(0, geometry.size.width - inset * 2))
            let panelWidth = wide ? (contentWidth - 24) / 2 : contentWidth
            let layout = wide
                ? AnyLayout(HStackLayout(alignment: .center, spacing: 24))
                : AnyLayout(VStackLayout(alignment: .leading, spacing: 16))

            ScrollView {
                layout {
                    introduction.frame(width: panelWidth)
                    form.frame(width: panelWidth)
                }
                .padding(inset)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .tint(Color(red: 0.05, green: 0.40, blue: 0.29))
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("MYMS", systemImage: "figure.strengthtraining.traditional")
                .font(.headline.weight(.semibold))
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(28)
        .foregroundStyle(.white)
        .background(
            LinearGradient(
                colors: [Color(red: 0.03, green: 0.23, blue: 0.19),
                         Color(red: 0.06, green: 0.40, blue: 0.29)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24)
        )
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            content
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }
}

@main
struct MYMSApp: App {
    @StateObject private var accounts = Accounts()

    var body: some Scene {
        WindowGroup {
            if let account = accounts.current {
                WorkoutHome(account: account, accounts: accounts).id(account.id)
            } else {
                LoginScreen(accounts: accounts)
            }
        }
    }
}

struct WorkoutHome: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var repFontSize = 68.0
    @StateObject private var coach = Coach()
    @StateObject private var store: WorkoutStore
    let account: LocalAccount
    @ObservedObject var accounts: Accounts
    @State private var confirmDeletion = false
    @State private var deletionPassword = ""

    init(account: LocalAccount, accounts: Accounts) {
        self.account = account
        self.accounts = accounts
        _store = StateObject(wrappedValue: WorkoutStore(token: accounts.token))
    }
    @State private var tab = 0
    @State private var editing: Workout?
    @State private var guide: Workout?
    @State private var deleting: Workout?
    @State private var deletingRecord: WorkoutRecord?

    var body: some View {
            TabView(selection: $tab) {
                plans.tabItem { Label("운동 계획", systemImage: "list.bullet") }.tag(0)
                session.tabItem { Label("운동", systemImage: "figure.strengthtraining.traditional") }.tag(1)
                history.tabItem { Label("기록", systemImage: "clock") }.tag(2)
                settings.tabItem { Label("설정", systemImage: "gearshape") }.tag(3)
            }
            .tint(Color(red: 0.16, green: 0.62, blue: 0.42))
            .onReceive(coach.$result.compactMap { $0 }) { store.save($0) }
            .task { await store.load() }
            .safeAreaInset(edge: .top) {
                if let error = store.syncError {
                    HStack {
                        Text(error).font(.footnote)
                        Spacer()
                        Button("다시 시도") { store.retry() }
                    }
                    .padding()
                    .background(.regularMaterial)
                } else if !store.loaded {
                    ProgressView("운동 데이터 불러오는 중").padding()
                }
            }
    }

    private var settings: some View {
        NavigationStack {
            Form {
                Section("내 계정") {
                    LabeledContent("이메일", value: account.email)
                    AgeGroupPicker(selection: Binding(
                        get: { accounts.current?.ageGroup },
                        set: { accounts.updateAgeGroup($0) }
                    ))
                    Text("Supabase 계정").foregroundStyle(.secondary)
                }
                Section {
                    Button("로그아웃") {
                        accounts.signOut()
                    }.disabled(!coach.canSelect || store.syncing || store.syncError != nil)
                    Button("회원 탈퇴", role: .destructive) {
                        deletionPassword = ""
                        confirmDeletion = true
                    }.disabled(!coach.canSelect || store.syncing || store.syncError != nil)
                } footer: {
                    if !coach.canSelect { Text("운동을 종료한 뒤 계정 설정을 변경할 수 있습니다.") }
                }
            }
            .navigationTitle("설정")
            .sheet(isPresented: $confirmDeletion, onDismiss: { accounts.message = nil }) {
                NavigationStack {
                    Form {
                        Section {
                            SecureField("비밀번호", text: $deletionPassword)
                        } header: {
                            Text("본인 확인")
                        } footer: {
                            Text("계정, 운동 계획, 기록과 포인트가 삭제됩니다.")
                        }
                        if let message = accounts.message {
                            Text(message).foregroundStyle(.red)
                        }
                        Button("계정과 운동 데이터 삭제", role: .destructive) {
                            Task {
                                if await accounts.delete(password: deletionPassword) {
                                    coach.stopConnection()
                                    confirmDeletion = false
                                }
                            }
                        }.disabled(deletionPassword.isEmpty)
                    }
                    .navigationTitle("회원 탈퇴")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("취소") { confirmDeletion = false }
                        }
                    }
                }
            }
        }
    }

    private var plans: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("누적 포인트").font(.subheadline)
                            Text("\(store.points) P").font(.largeTitle.bold()).monospacedDigit()
                        }
                        Spacer()
                        Image(systemName: "bolt.fill").font(.largeTitle)
                    }
                    .padding(.vertical, 10)
                    .foregroundStyle(.white)
                    .listRowBackground(Color(red: 0.05, green: 0.29, blue: 0.22))
                }
                Section("오늘의 운동") {
                    ForEach(store.plans) { plan in
                        Button {
                            guide = plan
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: plan.exercise.symbol).foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(plan.exercise.rawValue).font(.headline).foregroundStyle(.primary)
                                    Text("\(plan.level.title) · \(plan.target)회 × \(plan.sets)세트")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("운동 방법").font(.subheadline.weight(.medium)).foregroundStyle(.tint)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .leading) {
                            Button("편집", systemImage: "pencil") { editing = plan }.tint(.blue)
                        }
                        .swipeActions(allowsFullSwipe: false) {
                            Button("삭제", systemImage: "trash", role: .destructive) { deleting = plan }
                        }
                        .contextMenu {
                            Button("편집", systemImage: "pencil") { editing = plan }
                            Button("삭제", systemImage: "trash", role: .destructive) { deleting = plan }
                        }
                    }
                    if store.plans.isEmpty { Text("추가 버튼으로 운동 계획을 만드세요.").foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("운동 계획")
            .toolbar { Button("추가", systemImage: "plus") { editing = Workout() }.disabled(!store.loaded) }
            .sheet(item: $guide) { plan in
                ExerciseGuide(plan: plan, canSelect: coach.canSelect) {
                    coach.select(plan)
                    guide = nil
                    tab = 1
                }
            }
            .sheet(item: $editing) { plan in
                PlanEditor(plan: plan, ageGroup: account.ageGroup) { updated in
                    if let index = store.plans.firstIndex(where: { $0.id == updated.id }) {
                        store.plans[index] = updated
                    } else {
                        store.plans.append(updated)
                    }
                }
            }
            .confirmationDialog("운동 계획을 삭제할까요?", isPresented: Binding(
                get: { deleting != nil }, set: { if !$0 { deleting = nil } }
            ), titleVisibility: .visible) {
                Button("삭제", role: .destructive) {
                    if let deleting { store.plans.removeAll { $0.id == deleting.id } }
                    deleting = nil
                }
            }
        }
    }

    private var session: some View {
        NavigationStack {
            GeometryReader { geometry in
                let wide = geometry.size.width >= 780 && !typeSize.isAccessibilitySize
                let inset: CGFloat = wide ? 28 : 16
                let width = min(wide ? 960 : 540, max(0, geometry.size.width - inset * 2))
                let panelWidth = wide ? (width - 20) / 2 : width
                let layout = wide
                    ? AnyLayout(HStackLayout(alignment: .top, spacing: 20))
                    : AnyLayout(VStackLayout(spacing: 16))

                ScrollView {
                    layout {
                        sensorPanel.frame(width: panelWidth)
                        VStack(spacing: 16) {
                            progressPanel
                            sessionControls
                            sessionResult
                        }
                        .frame(width: panelWidth)
                    }
                    .padding(inset)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("운동")
        }
    }

    private var sensorPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if coach.canSelect || coach.isSimulating {
                Toggle("센서 없이 시연", isOn: Binding(
                    get: { coach.isSimulating },
                    set: { coach.setSimulation($0) }
                ))
                .disabled(!coach.canSelect)
            }

            VStack(alignment: .leading, spacing: 8) {
                Label(coach.isSimulating ? "시연 모드 · 가상 센서" : coach.connection,
                      systemImage: coach.isSimulating ? "waveform" : "antenna.radiowaves.left.and.right")
                    .font(.headline)
                if let millimeters = coach.latestDistance {
                    Text("\((millimeters / 10).formatted(.number.precision(.fractionLength(1)))) cm")
                        .font(.title2.monospacedDigit())
                } else {
                    Text(coach.connected ? "유효 거리값 대기 중" : "센서 데이터 대기 중")
                        .foregroundStyle(.secondary)
                }
                if coach.isSimulating {
                    Text("시연 기록과 포인트는 저장되지 않습니다.")
                        .foregroundStyle(.secondary)
                } else if coach.canSelect {
                    Text(coach.workout.exercise.placement).foregroundStyle(.secondary)
                } else if coach.phase == .training && coach.latestDistance == nil {
                    Text("측정 일시 중지").foregroundStyle(.orange)
                }
                if coach.phase == .calibrating {
                    ProgressView(value: coach.calibrationProgress)
                        .accessibilityLabel("시작 거리 측정 진행률")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private var progressPanel: some View {
        VStack(spacing: 8) {
            Text(coach.workout.exercise.rawValue).font(.title2.bold())
            Text("\(coach.workout.level.title) · 세트 \(coach.set) / \(coach.workout.sets)")
            Text("\(coach.reps) / \(coach.workout.target)")
                .font(.system(size: repFontSize, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5).lineLimit(1).monospacedDigit()
                .accessibilityLabel("\(coach.workout.target)회 중 \(coach.reps)회")
            ProgressView(value: Double(coach.reps), total: Double(coach.workout.target)).tint(.mint)
            Text(coach.phase.rawValue).font(.headline)
            if coach.phase == .resting {
                Text("남은 휴식 \(coach.restSeconds)초").monospacedDigit()
            }
            if coach.shallow {
                Text("동작 범위를 조금 더 늘려 보세요").foregroundStyle(.yellow)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .foregroundStyle(.white)
        .background(Color(red: 0.05, green: 0.29, blue: 0.22), in: RoundedRectangle(cornerRadius: 24))
    }

    @ViewBuilder
    private var sessionResult: some View {
        if coach.phase == .finished, let summary = coach.summary {
            VStack(alignment: .leading, spacing: 8) {
                Text(coach.isSimulating ? "시연 결과" : "운동 결과").font(.headline)
                LabeledContent("유효 횟수", value: "\(summary.reps)회")
                LabeledContent("완료 세트", value: "\(summary.sets) / \(summary.workout.sets)")
                LabeledContent("경과 시간", value: "\(summary.seconds)초")
                if let saved = store.records.first(where: { $0.id == summary.id }) {
                    LabeledContent("획득 포인트", value: "\(saved.points) P")
                }
            }
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private var sessionControls: some View {
        VStack(spacing: 12) {
            if coach.isSimulating && coach.phase == .training {
                Button("가상 동작 1회") { coach.simulateRep() }
                    .disabled(coach.isSimulatingRep)
            }
            switch coach.phase {
            case .ready, .finished:
                Button("운동 시작") { coach.gesture(4) }.disabled(!coach.canMeasure || !store.loaded)
            case .calibrating, .training:
                Button("일시정지") { coach.pause() }
            case .paused:
                Button("재개") { coach.gesture(4) }.disabled(!coach.canMeasure || !store.loaded)
                Button("운동 종료") { coach.finish() }
            case .resting:
                Button("다음 세트") { coach.gesture(1) }.disabled(!coach.canMeasure || !store.loaded)
                Button("운동 종료") { coach.finish() }
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private var history: some View {
        NavigationStack {
            List {
                if store.records.isEmpty {
                    ContentUnavailableView("운동 기록이 없어요", systemImage: "clock", description: Text("센서로 측정한 운동이 여기에 저장됩니다."))
                }
                ForEach(store.records) { record in
                    NavigationLink {
                        Form {
                            Section("운동 결과") {
                                LabeledContent("운동", value: record.workout.exercise.rawValue)
                                LabeledContent("난이도", value: record.workout.level.title)
                                LabeledContent("유효 횟수", value: "\(record.reps)회")
                                LabeledContent("완료 세트", value: "\(record.sets) / \(record.workout.sets)")
                                LabeledContent("경과 시간", value: "\(record.seconds)초")
                                LabeledContent("획득 포인트", value: "\(record.points) P")
                            }
                            Section("메모") {
                                TextField("운동 메모", text: Binding(
                                    get: { store.records.first { $0.id == record.id }?.note ?? "" },
                                    set: { note in
                                        if let index = store.records.firstIndex(where: { $0.id == record.id }) {
                                            store.records[index].note = note
                                        }
                                    }
                                ), axis: .vertical)
                            }
                        }
                        .navigationTitle("운동 결과")
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.workout.exercise.rawValue).font(.headline)
                            Text(record.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text("\(record.workout.level.title) · \(record.reps)회 · \(record.points) P")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(allowsFullSwipe: false) {
                        Button("삭제", systemImage: "trash", role: .destructive) { deletingRecord = record }
                    }
                }
            }
            .navigationTitle("운동 기록")
            .confirmationDialog("기록과 적립 포인트를 삭제할까요?", isPresented: Binding(
                get: { deletingRecord != nil }, set: { if !$0 { deletingRecord = nil } }
            ), titleVisibility: .visible) {
                Button("삭제", role: .destructive) {
                    if let deletingRecord { store.records.removeAll { $0.id == deletingRecord.id } }
                    deletingRecord = nil
                }
            }
        }
    }
}

private struct ExerciseAnimation: View {
    let exercise: Exercise
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt: Date?
    @State private var elapsed = 0.0

    private let cycle = 3.2

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: startedAt == nil)) { timeline in
                let motion = elapsed + (startedAt.map { max(0, timeline.date.timeIntervalSince($0)) } ?? 0)
                let phase = (1 - cos(motion / cycle * 2 * .pi)) / 2
                illustration(phase: phase)
                    .overlay(alignment: .bottomLeading) {
                        Text(phase < 0.5 ? "시작 자세" : (exercise == .pushup || exercise == .squat ? "내린 자세" : "들어 올린 자세"))
                            .font(.caption.weight(.semibold))
                            .padding(8)
                    }
                    .accessibilityHidden(true)
            }
            HStack {
                Button {
                    if let startedAt {
                        elapsed = (elapsed + Date().timeIntervalSince(startedAt)).truncatingRemainder(dividingBy: cycle)
                        self.startedAt = nil
                    } else {
                        startedAt = Date()
                    }
                } label: {
                    Label(startedAt == nil ? "재생" : "일시정지",
                          systemImage: startedAt == nil ? "play.fill" : "pause.fill")
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("자세 전환") {
                    startedAt = nil
                    elapsed = elapsed < cycle / 4 ? cycle / 2 : 0
                }
                .buttonStyle(.bordered)
            }
        }
        .onAppear {
            if !reduceMotion { startedAt = Date() }
        }
        .onDisappear { startedAt = nil }
    }

    private func illustration(phase: Double) -> some View {
        let poses = exercise.demonstration
        return Canvas { context, size in
            let scale = min(size.width / 100, size.height / 76)
            func point(_ x: Double, _ y: Double) -> CGPoint {
                CGPoint(x: (size.width - 100 * scale) / 2 + x * scale,
                        y: (size.height - 76 * scale) / 2 + y * scale)
            }
            func joint(_ index: Int) -> CGPoint {
                let a = poses.start[index]
                let b = poses.end[index]
                return point(a.x + (b.x - a.x) * phase, a.y + (b.y - a.y) * phase)
            }
            func line(_ points: [CGPoint], color: Color, width: Double) {
                var path = Path()
                path.addLines(points)
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            }
            let ink = Color(red: 0.06, green: 0.32, blue: 0.25)
            line([point(9, 64), point(91, 64)], color: ink.opacity(0.22), width: 2)
            if exercise == .kneeRaise {
                line([point(36, 44), point(57, 44), point(57, 63)], color: ink.opacity(0.35), width: 3)
                line([point(36, 44), point(36, 63)], color: ink.opacity(0.35), width: 3)
                line([joint(2), point(63, 47), point(64, 62)], color: ink.opacity(0.35), width: 4)
            }
            line([joint(0), joint(1), joint(2), joint(3), joint(4)], color: ink, width: 5)
            line([joint(1), joint(5), joint(6)], color: ink, width: 4)
            let head = joint(0)
            let radius = 5.2 * scale
            context.fill(Path(ellipseIn: CGRect(x: head.x - radius, y: head.y - radius,
                                                width: radius * 2, height: radius * 2)), with: .color(ink))
        }
        .frame(height: 200)
        .background(Color(red: 0.90, green: 0.96, blue: 0.93), in: RoundedRectangle(cornerRadius: 16))
        .foregroundStyle(Color(red: 0.06, green: 0.32, blue: 0.25))
    }
}

private extension Exercise {
    // Joint order is head, shoulder, hip, knee, foot, elbow, hand.
    var demonstration: (start: [CGPoint], end: [CGPoint]) {
        let positions: ([(Double, Double)], [(Double, Double)])
        switch self {
        case .pushup:
            positions = ([(75, 24), (64, 32), (42, 45), (28, 54), (14, 63), (67, 48), (68, 63)],
                         [(78, 46), (66, 50), (43, 54), (28, 58), (14, 63), (56, 57), (68, 63)])
        case .squat:
            positions = ([(49, 10), (49, 20), (48, 37), (49, 50), (49, 63), (55, 29), (61, 34)],
                         [(57, 23), (51, 32), (39, 47), (55, 50), (49, 63), (61, 31), (72, 28)])
        case .bridge:
            positions = ([(20, 59), (29, 60), (50, 61), (64, 43), (75, 63), (39, 63), (52, 63)],
                         [(20, 59), (29, 60), (49, 46), (64, 38), (75, 63), (39, 63), (52, 63)])
        case .kneeRaise:
            positions = ([(43, 12), (44, 23), (45, 43), (64, 45), (67, 63), (49, 35), (57, 41)],
                         [(43, 12), (44, 23), (45, 43), (64, 32), (73, 49), (47, 34), (57, 41)])
        }
        return (positions.0.map { CGPoint(x: $0.0, y: $0.1) },
                positions.1.map { CGPoint(x: $0.0, y: $0.1) })
    }
}

struct ExerciseGuide: View {
    @Environment(\.dismiss) private var dismiss
    let plan: Workout
    let canSelect: Bool
    var onSelect: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: plan.exercise.symbol).font(.title)
                        Text(plan.exercise.rawValue).font(.largeTitle.bold())
                        Text("\(plan.level.title) · \(plan.target)회 × \(plan.sets)세트 · 휴식 \(plan.rest)초")
                            .font(.subheadline)
                    }
                    .padding(.vertical, 8)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .listRowBackground(Color(red: 0.05, green: 0.29, blue: 0.22))
                }
                Section("운동 방법") {
                    ExerciseAnimation(exercise: plan.exercise)
                    ForEach(plan.exercise.steps.indices, id: \.self) { index in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("\(index + 1)").font(.headline.monospacedDigit()).foregroundStyle(.tint)
                            Text(plan.exercise.steps[index])
                        }
                    }
                }
                Section("센서 배치와 시작 자세") {
                    Text(plan.exercise.placement)
                    Text("운동을 시작하면 앱이 2초 동안 시작 높이를 측정합니다. 화면에 ‘운동 중’이 표시될 때까지 첫 자세를 유지하세요.")
                    if let note = plan.exercise.measurementNote {
                        Label(note, systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    ForEach(Level.allCases, id: \.self) { level in
                        LabeledContent(level.title, value: plan.exercise.depth(for: level).formatted(.percent))
                            .fontWeight(level == plan.level ? .semibold : .regular)
                    }
                } header: {
                    Text("난이도별 거리 변화 기준")
                } footer: {
                    Text("시작 거리보다 센서에 해당 비율만큼 가까워졌다가, 시작 거리와의 차이가 \(plan.exercise.returnDepth.formatted(.percent)) 이하로 돌아오면 1회로 셉니다. 앱은 센서 거리로 횟수를 판정합니다.")
                }
            }
            .navigationTitle("운동 안내")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("이 운동 준비하기", action: onSelect)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!canSelect)
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(.regularMaterial)
            }
        }
    }
}

struct AgeGroupPicker: View {
    @Binding var selection: AgeGroup?

    var body: some View {
        Picker("연령대", selection: $selection) {
            Text("선택").tag(nil as AgeGroup?)
            ForEach(AgeGroup.allCases, id: \.self) { group in
                Text(group.rawValue).tag(Optional(group))
            }
        }
    }
}

struct PlanEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var plan: Workout
    let ageGroup: AgeGroup?
    @State private var experience = Level.easy
    var onSave: (Workout) -> Void

    private var recommendedReps: Int {
        let base: Int
        switch plan.exercise {
        case .pushup: base = 5
        case .squat: base = 8
        case .bridge: base = 7
        case .kneeRaise: base = 6
        }
        return base + (experience.rawValue - 1) * 2 - (ageGroup?.volumeAdjustment ?? 0)
    }

    private var recommendedSets: Int {
        let reduction = ageGroup?.volumeAdjustment == 2 ? 1 : 0
        return max(1, experience.rawValue - reduction)
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("운동 종류", selection: $plan.exercise) {
                    ForEach(Exercise.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Section {
                    Picker("운동 경험", selection: $experience) {
                        ForEach(Level.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    LabeledContent("추천", value: "\(experience.title) · \(recommendedReps)회 × \(recommendedSets)세트")
                    Button("추천값 적용") {
                        plan.level = experience
                        plan.target = recommendedReps
                        plan.sets = recommendedSets
                    }
                } header: {
                    Text(ageGroup.map { "\($0.rawValue) 운동 추천" } ?? "운동 추천")
                } footer: {
                    Text(ageGroup == nil
                         ? "설정에서 연령대를 선택하면 추천값에 반영됩니다."
                         : "선택한 운동과 경험에 따른 시작값입니다. 적용 후 직접 바꿀 수 있습니다.")
                }
                Picker("난이도", selection: $plan.level) {
                    ForEach(Level.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                LabeledContent("깊이 기준", value: plan.exercise.depth(for: plan.level).formatted(.percent))
                Stepper("목표 \(plan.target)회", value: $plan.target, in: 1...100)
                Stepper("\(plan.sets)세트", value: $plan.sets, in: 1...10)
                Stepper("휴식 \(plan.rest)초", value: $plan.rest, in: 5...300, step: 5)
            }
            .navigationTitle("운동 설정")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { onSave(plan); dismiss() }
                }
            }
        }
    }
}

final class Coach: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    enum Phase: String {
        case ready = "대기", calibrating = "시작 자세를 유지하세요", training = "운동 중"
        case paused = "일시정지", resting = "휴식", finished = "운동 종료"
    }

    @Published private(set) var phase = Phase.ready
    @Published private(set) var connection = "Bluetooth 준비 중"
    @Published private(set) var connected = false
    @Published private(set) var reps = 0
    @Published private(set) var set = 1
    @Published private(set) var restSeconds = 30
    @Published private(set) var shallow = false
    @Published private(set) var workout = Workout()
    @Published private(set) var result: WorkoutRecord?
    @Published private(set) var summary: WorkoutRecord?
    @Published private(set) var latestDistance: Double?
    @Published private(set) var calibrationProgress = 0.0
    @Published private(set) var isSimulating = false
    @Published private(set) var isSimulatingRep = false
    private var simulationTimer: Timer?
    private var simulationSample = 0
    private var lastLiveSample: TimeInterval?
    private var distanceTimer: Timer?

    var canMeasure: Bool { latestDistance != nil && (isSimulating || connected) }

    func setSimulation(_ enabled: Bool) {
        guard canSelect, enabled != isSimulating else { return }
        isSimulating = enabled
        phase = .ready
        reps = 0
        set = 1
        summary = nil
        resetMotion()
        latestDistance = nil
        if enabled {
            measure(400)
            simulationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.feedSimulation()
            }
        } else {
            simulationTimer?.invalidate()
            simulationTimer = nil
        }
    }

    func simulateRep() {
        guard isSimulating, phase == .training, !isSimulatingRep else { return }
        simulationSample = 0
        isSimulatingRep = true
    }

    private func feedSimulation() {
        guard isSimulating else { return }
        if isSimulatingRep && phase == .training {
            simulationSample += 1
            let depth = workout.exercise.depth(for: workout.level) + 0.05
            measure(simulationSample <= 8 ? 400 * (1 - depth) : 400)
            if simulationSample >= 12 { isSimulatingRep = false }
        } else {
            isSimulatingRep = false
            measure(400)
        }
    }
    private var sessionStart = Date()
    private var totalReps = 0
    private var completedSets = 0

    var canSelect: Bool { phase == .ready || phase == .finished }

    func select(_ plan: Workout) {
        guard canSelect else { return }
        workout = plan
        reps = 0
        set = 1
        phase = .ready
    }

    func finish() {
        restTimer?.invalidate()
        resetMotion()
        phase = .finished
        guard totalReps > 0 else { return }
        let completed = WorkoutRecord(workout: workout, reps: totalReps, sets: completedSets,
                               seconds: max(0, Int(Date().timeIntervalSince(sessionStart))),
                               points: totalReps * workout.level.rawValue + completedSets * 5)
        summary = completed
        if !isSimulating { result = completed }
    }

    private let suffix = "-E8F2-537E-4F6C-D104768A1214"
    private lazy var service = CBUUID(string: "19B10000" + suffix)
    private lazy var distance = CBUUID(string: "19B10004" + suffix)
    private lazy var gestureID = CBUUID(string: "19B10005" + suffix)
    private var central: CBCentralManager!
    private var sensor: CBPeripheral?
    private var samples: [Double] = []
    private var calibration: [Double] = []
    private var calibrationStart: TimeInterval?
    private var baseline = 0.0
    private var descent: TimeInterval?
    private var reachedDepth = false
    private var restDeadline = Date.distantPast
    private var restTimer: Timer?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
        distanceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, !self.isSimulating, let last = self.lastLiveSample,
                  ProcessInfo.processInfo.systemUptime - last > 1 else { return }
            self.lastLiveSample = nil
            self.measure(0)
        }
    }

    deinit {
        simulationTimer?.invalidate()
        distanceTimer?.invalidate()
        restTimer?.invalidate()
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            connected = false
            if !isSimulating { measure(0) }
            connection = "Bluetooth 상태를 확인하세요"
            return
        }
        scan()
    }

    func stopConnection() {
        simulationTimer?.invalidate()
        distanceTimer?.invalidate()
        central.stopScan()
        if let sensor { central.cancelPeripheralConnection(sensor) }
        sensor?.delegate = nil
        central.delegate = nil
    }

    private func scan() {
        guard central.state == .poweredOn else { return }
        connection = "MYMS 센서 검색 중"
        central.scanForPeripherals(withServices: [service])
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        central.stopScan()
        sensor = peripheral
        peripheral.delegate = self
        connection = "연결 중"
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        scan()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connected = false
        if !isSimulating { measure(0) }
        scan()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let fitness = peripheral.services?.first(where: { $0.uuid == service }) else {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        peripheral.discoverCharacteristics([distance, gestureID], for: fitness)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let characteristics = service.characteristics ?? []
        guard characteristics.contains(where: { $0.uuid == distance }) else {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        for characteristic in characteristics where characteristic.properties.contains(.notify) {
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == distance else { return }
        connected = characteristic.isNotifying && error == nil
        connection = connected ? "센서 연결됨" : "거리 수신 실패"
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard !isSimulating, error == nil, let data = characteristic.value, data.count == 2 else { return }
        let bytes = Array(data)
        if characteristic.uuid == distance {
            lastLiveSample = ProcessInfo.processInfo.systemUptime
            measure(Double(Int(bytes[0]) + Int(bytes[1]) * 256))
        } else if characteristic.uuid == gestureID {
            gesture(bytes[0])
        }
    }

    func gesture(_ direction: UInt8) {
        switch (direction, phase) {
        case (4, .ready), (4, .finished):
            guard canMeasure else { return }
            reps = 0
            set = 1
            totalReps = 0
            completedSets = 0
            summary = nil
            sessionStart = Date()
            calibrate()
        case (4, .paused):
            guard canMeasure else { return }
            calibrate()
        case (3, .training), (3, .calibrating):
            guard descent == nil else { return }
            pause()
        case (1, .resting):
            guard canMeasure else { return }
            restTimer?.invalidate()
            set += 1
            reps = 0
            calibrate()
        case (2, .paused):
            finish()
        default:
            break
        }
    }

    func pause() {
        guard phase == .training || phase == .calibrating else { return }
        resetMotion()
        phase = .paused
    }

    private func calibrate() {
        resetMotion()
        phase = .calibrating
    }

    private func resetMotion() {
        samples.removeAll()
        calibration.removeAll()
        calibrationStart = nil
        calibrationProgress = 0
        isSimulatingRep = false
        descent = nil
        reachedDepth = false
        shallow = false
    }

    private func measure(_ millimeters: Double) {
        guard millimeters > 0 else {
            latestDistance = nil
            resetMotion()
            return
        }
        latestDistance = millimeters
        guard phase == .calibrating || phase == .training else { return }

        samples.append(millimeters)
        if samples.count > 3 { samples.removeFirst() }
        guard samples.count == 3 else { return }
        let filtered = samples.sorted()[1]
        let now = ProcessInfo.processInfo.systemUptime

        if phase == .calibrating {
            if calibrationStart == nil { calibrationStart = now }
            calibration.append(filtered)
            if let start = calibrationStart {
                calibrationProgress = min(1, (now - start) / 2)
                if calibrationProgress == 1 {
                    baseline = calibration.reduce(0, +) / Double(calibration.count)
                    phase = .training
                }
            }
            return
        }

        let depth = (baseline - filtered) / baseline
        if depth > (workout.exercise.returnDepth + 0.03), descent == nil {
            descent = now
            shallow = false
        }
        if depth >= workout.exercise.depth(for: workout.level) { reachedDepth = true }
        guard depth <= workout.exercise.returnDepth, let start = descent else { return }
        descent = nil
        defer { reachedDepth = false }
        guard now - start >= 0.5 else { return }
        shallow = !reachedDepth
        guard reachedDepth else { return }
        reps += 1
        totalReps += 1
        guard reps == workout.target else { return }
        completedSets += 1
        if set == workout.sets {
            finish()
        } else {
            phase = .resting
            restSeconds = workout.rest
            restDeadline = Date().addingTimeInterval(Double(workout.rest))
            restTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.restSeconds = max(0, Int(ceil(self.restDeadline.timeIntervalSinceNow)))
                if self.restSeconds == 0 { self.gesture(1) }
            }
        }
    }
}
