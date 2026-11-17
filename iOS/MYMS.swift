import CoreBluetooth
import Security
import SwiftUI

enum Exercise: String, Codable, CaseIterable {
    case pushup = "푸시업", squat = "스쿼트"
    case bridge = "힙 브리지", kneeRaise = "앉아서 무릎 들기"

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

struct Workout: Codable, Identifiable {
    var id = UUID()
    var exercise = Exercise.pushup
    var level = Level.normal
    var target = 10
    var sets = 3
    var rest = 30
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

final class WorkoutStore: ObservableObject {
    private let namespace: String
    @Published var plans: [Workout] {
        didSet { save(plans, key: "myms.plans") }
    }

    @Published var records: [WorkoutRecord] {
        didSet { save(records, key: "myms.records") }
    }

    var points: Int { records.reduce(0) { $0 + $1.points } }

    init(accountID: UUID) {
        namespace = Self.namespace(for: accountID)
        plans = Self.load(namespace + "myms.plans") ?? Exercise.allCases.map { Workout(exercise: $0, level: $0 == .pushup ? .normal : .easy) }
        records = Self.load(namespace + "myms.records") ?? []
    }

    static func namespace(for accountID: UUID) -> String {
        "myms.account.\(accountID.uuidString)."
    }

    static func migrateLegacyData(to accountID: UUID) {
        let defaults = UserDefaults.standard
        for key in ["myms.plans", "myms.records"] {
            guard let data = defaults.data(forKey: key) else { continue }
            defaults.set(data, forKey: namespace(for: accountID) + key)
            defaults.removeObject(forKey: key)
        }
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: namespace + key)
    }

    func save(_ record: WorkoutRecord) {
        guard !records.contains(where: { $0.id == record.id }) else { return }
        var entry = record
        let today = records.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.points }
        entry.points = min(entry.points, max(0, 300 - today))
        records.insert(entry, at: 0)
    }
}

enum AgeGroup: String, Codable, CaseIterable {
    case teens = "10대", twenties = "20대", thirties = "30대", forties = "40대"
    case fifties = "50대", sixties = "60대", older = "70대 이상"

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

final class Accounts: ObservableObject {
    @Published private(set) var current: LocalAccount?
    @Published var message: String?

    private let keychainService = "edu.myms.fitness.accounts"
    private let accountKey = "myms.accounts"
    private var entries: [LocalAccount] {
        guard let data = UserDefaults.standard.data(forKey: accountKey) else { return [] }
        return (try? JSONDecoder().decode([LocalAccount].self, from: data)) ?? []
    }

    func register(email: String, password: String, ageGroup: AgeGroup) {
        let address = normalize(email)
        guard address.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil else {
            message = "이메일 주소를 확인해 주세요."
            return
        }
        guard password.count >= 8 else {
            message = "비밀번호를 8자 이상 입력해 주세요."
            return
        }
        guard !entries.contains(where: { $0.email == address }) else {
            message = "이미 가입한 이메일입니다."
            return
        }

        let account = LocalAccount(id: UUID(), email: address, ageGroup: ageGroup)
        guard let data = try? JSONEncoder().encode(entries + [account]) else { return }
        var attributes = query(account)
        attributes[kSecValueData as String] = Data(password.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else {
            message = "계정 정보를 저장하지 못했습니다."
            return
        }
        WorkoutStore.migrateLegacyData(to: account.id)
        UserDefaults.standard.set(data, forKey: accountKey)
        message = nil
        current = account
    }

    func signIn(email: String, password: String) {
        guard let account = entries.first(where: { $0.email == normalize(email) }),
              matches(password, account: account) else {
            message = "이메일 또는 비밀번호를 확인해 주세요."
            return
        }
        message = nil
        current = account
    }

    func updateAgeGroup(_ ageGroup: AgeGroup?) {
        guard var account = current else { return }
        var updated = entries
        guard let index = updated.firstIndex(where: { $0.id == account.id }) else { return }
        account.ageGroup = ageGroup
        updated[index] = account
        guard let data = try? JSONEncoder().encode(updated) else { return }
        UserDefaults.standard.set(data, forKey: accountKey)
        current = account
    }

    func signOut() {
        message = nil
        current = nil
    }

    func delete(password: String) -> Bool {
        guard let account = current, matches(password, account: account) else {
            message = "비밀번호를 확인해 주세요."
            return false
        }
        guard let data = try? JSONEncoder().encode(entries.filter { $0.id != account.id }),
              SecItemDelete(query(account) as CFDictionary) == errSecSuccess else {
            message = "계정을 삭제하지 못했습니다. 다시 시도해 주세요."
            return false
        }
        let prefix = WorkoutStore.namespace(for: account.id)
        UserDefaults.standard.removeObject(forKey: prefix + "myms.plans")
        UserDefaults.standard.removeObject(forKey: prefix + "myms.records")
        UserDefaults.standard.set(data, forKey: accountKey)
        signOut()
        return true
    }

    private func normalize(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func query(_ account: LocalAccount) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account.id.uuidString
        ]
    }

    private func matches(_ password: String, account: LocalAccount) -> Bool {
        var attributes = query(account)
        attributes[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(attributes as CFDictionary, &result) == errSecSuccess,
              let stored = result as? Data else { return false }
        return stored == Data(password.utf8)
    }
}

struct LoginScreen: View {
    @ObservedObject var accounts: Accounts
    @State private var registering = false
    @State private var ageGroup: AgeGroup?
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "figure.strengthtraining.traditional").font(.largeTitle)
                        Text("MYMS").font(.largeTitle.bold())
                        Text("운동 계획과 기록을 이 기기에 저장합니다.").font(.subheadline)
                    }
                    .padding(.vertical, 14)
                    .foregroundStyle(.white)
                    .listRowBackground(Color(red: 0.05, green: 0.29, blue: 0.22))
                }
                Section {
                    TextField("이메일", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("비밀번호", text: $password)
                        .textContentType(registering ? .newPassword : .password)
                    if registering {
                        AgeGroupPicker(selection: $ageGroup)
                    }
                } footer: {
                    if let message = accounts.message { Text(message).foregroundStyle(.red) }
                    else if registering { Text("비밀번호는 8자 이상으로 설정하세요.") }
                }
                Section {
                    Button(registering ? "회원가입" : "로그인") {
                        if registering {
                            guard let ageGroup else { return }
                            accounts.register(email: email, password: password, ageGroup: ageGroup)
                        } else {
                            accounts.signIn(email: email, password: password)
                        }
                    }
                    .disabled(email.isEmpty || password.isEmpty || (registering && ageGroup == nil))
                    Button(registering ? "로그인으로 돌아가기" : "새 계정 만들기") {
                        registering.toggle()
                        password = ""
                        accounts.message = nil
                    }
                }
            }
            .navigationTitle(registering ? "회원가입" : "로그인")
            .tint(Color(red: 0.16, green: 0.62, blue: 0.42))
        }
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
    @StateObject private var coach = Coach()
    @StateObject private var store: WorkoutStore
    let account: LocalAccount
    @ObservedObject var accounts: Accounts
    @State private var confirmDeletion = false
    @State private var deletionPassword = ""

    init(account: LocalAccount, accounts: Accounts) {
        self.account = account
        self.accounts = accounts
        _store = StateObject(wrappedValue: WorkoutStore(accountID: account.id))
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
                    Text("이 기기에 저장된 계정입니다.").foregroundStyle(.secondary)
                }
                Section {
                    Button("로그아웃") {
                        coach.stopConnection()
                        accounts.signOut()
                    }.disabled(!coach.canSelect)
                    Button("회원 탈퇴", role: .destructive) {
                        deletionPassword = ""
                        confirmDeletion = true
                    }.disabled(!coach.canSelect)
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
                            Text("계정, 운동 계획, 기록과 포인트가 이 기기에서 삭제됩니다.")
                        }
                        if let message = accounts.message {
                            Text(message).foregroundStyle(.red)
                        }
                        Button("계정과 운동 데이터 삭제", role: .destructive) {
                            if accounts.delete(password: deletionPassword) {
                                coach.stopConnection()
                                confirmDeletion = false
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
            .toolbar { Button("추가", systemImage: "plus") { editing = Workout() } }
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
            ScrollView {
                VStack(spacing: 24) {
                    Label(coach.connection, systemImage: coach.connected ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right")
                        .font(.subheadline.weight(.medium))
                    VStack(spacing: 8) {
                        Text(coach.workout.exercise.rawValue).font(.title2.bold())
                        Text("\(coach.workout.level.title) · 세트 \(coach.set) / \(coach.workout.sets)")
                        Text("\(coach.reps) / \(coach.workout.target)")
                            .font(.system(size: 68, weight: .bold, design: .rounded))
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
                    .padding(24)
                    .foregroundStyle(.white)
                    .background(Color(red: 0.05, green: 0.29, blue: 0.22), in: RoundedRectangle(cornerRadius: 24))
                    switch coach.phase {
                    case .ready, .finished:
                        Button("운동 시작") { coach.gesture(4) }.disabled(!coach.connected)
                    case .calibrating, .training:
                        Button("일시정지") { coach.pause() }
                    case .paused:
                        Button("재개") { coach.gesture(4) }.disabled(!coach.connected)
                        Button("운동 종료") { coach.finish() }
                    case .resting:
                        Button("다음 세트") { coach.gesture(1) }.disabled(!coach.connected)
                        Button("운동 종료") { coach.finish() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
            }
            .navigationTitle("운동")
        }
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
        result = WorkoutRecord(workout: workout, reps: totalReps, sets: completedSets,
                               seconds: max(0, Int(Date().timeIntervalSince(sessionStart))),
                               points: totalReps * workout.level.rawValue + completedSets * 5)
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
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            connected = false
            connection = "Bluetooth 상태를 확인하세요"
            return
        }
        scan()
    }

    func stopConnection() {
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
        resetMotion()
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
        guard error == nil, let data = characteristic.value, data.count == 2 else { return }
        let bytes = Array(data)
        if characteristic.uuid == distance {
            measure(Double(Int(bytes[0]) + Int(bytes[1]) * 256))
        } else if characteristic.uuid == gestureID {
            gesture(bytes[0])
        }
    }

    func gesture(_ direction: UInt8) {
        switch (direction, phase) {
        case (4, .ready), (4, .finished):
            guard connected else { return }
            reps = 0
            set = 1
            totalReps = 0
            completedSets = 0
            sessionStart = Date()
            calibrate()
        case (4, .paused):
            guard connected else { return }
            calibrate()
        case (3, .training), (3, .calibrating):
            guard descent == nil else { return }
            pause()
        case (1, .resting):
            guard connected else { return }
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
        descent = nil
        reachedDepth = false
        shallow = false
    }

    private func measure(_ millimeters: Double) {
        guard phase == .calibrating || phase == .training else { return }
        guard millimeters > 0 else {
            resetMotion()
            return
        }

        samples.append(millimeters)
        if samples.count > 3 { samples.removeFirst() }
        guard samples.count == 3 else { return }
        let filtered = samples.sorted()[1]
        let now = ProcessInfo.processInfo.systemUptime

        if phase == .calibrating {
            if calibrationStart == nil { calibrationStart = now }
            calibration.append(filtered)
            if let start = calibrationStart, now - start >= 2 {
                baseline = calibration.reduce(0, +) / Double(calibration.count)
                phase = .training
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
