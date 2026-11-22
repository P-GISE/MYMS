import Foundation
import Combine

@MainActor
final class WorkoutStore: ObservableObject {
    @Published var plans: [Workout] = [] {
        didSet { if loaded && !applying { queuePlanChanges(from: oldValue) } }
    }
    @Published var records: [WorkoutRecord] = [] {
        didSet { if loaded && !applying { queueRecordChanges(from: oldValue) } }
    }
    @Published private(set) var loaded = false
    @Published private(set) var syncError: String?
    @Published private(set) var syncing = false

    private let accounts: Accounts
    private let pendingKey: String
    /// 서버에서 받은 내용을 화면에 반영하는 중이라, 그 변경을 다시 서버로 보내지 않습니다.
    private var applying = false
    /// 서버가 거부한 변경이 있어, 화면을 서버에 저장된 내용으로 되돌려야 합니다.
    private var rejected = false
    /// 서버에 아직 보내지 못한 변경입니다. 앱이 꺼져도 남도록 바뀔 때마다 기기에 저장합니다.
    private var pending: [Mutation] {
        didSet {
            if pending.isEmpty { UserDefaults.standard.removeObject(forKey: pendingKey) }
            else { UserDefaults.standard.set(try? JSONEncoder().encode(pending), forKey: pendingKey) }
        }
    }

    private struct Mutation: Codable {
        let path: String
        let method: String
        var body: Data?
        var prefer: String?

        init(path: String, method: String, fields: [String: Any]? = nil, prefer: String? = nil) {
            self.path = path
            self.method = method
            self.body = fields.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
            self.prefer = prefer
        }

        var fields: [String: Any]? {
            body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        }
    }

    var points: Int { records.reduce(0) { $0 + $1.points } }

    init(accounts: Accounts, accountID: UUID) {
        self.accounts = accounts
        pendingKey = Self.namespace(for: accountID) + "myms.pending"
        pending = UserDefaults.standard.data(forKey: pendingKey)
            .flatMap { try? JSONDecoder().decode([Mutation].self, from: $0) } ?? []
    }

    static func namespace(for accountID: UUID) -> String {
        "myms.account.\(accountID.uuidString)."
    }

    func load() async {
        guard !loaded, !syncing else { return }
        syncing = true
        await sync()
    }

    func retry() {
        syncError = nil
        if loaded { flush() }
        else { Task { await load() } }
    }

    private func flush() {
        guard !syncing, !pending.isEmpty || rejected else { return }
        syncing = true
        Task { await sync() }
    }

    /// 쌓인 변경을 먼저 보냅니다. 처음 불러올 때와 서버가 변경을 거부했을 때는 이어서 서버 내용을 받아 화면에 반영합니다.
    private func sync() async {
        syncError = nil
        defer { syncing = false }
        do {
            try await drain()
            guard !loaded || rejected else { return }
            var rows = try await fetch()
            while !pending.isEmpty {
                try await drain()
                rows = try await fetch()
            }
            applying = true
            plans = rows.plans
            records = rows.records
            applying = false
            loaded = true
            if rejected {
                rejected = false
                syncError = "서버가 저장하지 못한 변경이 있어 서버에 저장된 내용으로 되돌렸습니다."
            }
        } catch {
            syncError = error.localizedDescription
        }
    }

    /// 일시적인 오류면 멈추고 큐를 그대로 둡니다. 데이터 자체가 거부된 변경은 다시 보내도 같으므로 버리고 다음으로 넘어갑니다.
    private func drain() async throws {
        while let next = pending.first {
            do {
                _ = try await accounts.request(next.path, method: next.method,
                                               body: next.fields, prefer: next.prefer)
            } catch let error as MYMSCloud.RequestError where error.rejectsData {
                rejected = true
            }
            pending.removeFirst()
        }
    }

    private func fetch() async throws -> (plans: [Workout], records: [WorkoutRecord]) {
        async let planData = accounts.request("/rest/v1/workout_plans?order=sort_order.asc,id.asc")
        async let sessionData = accounts.request("/rest/v1/workout_sessions?order=finished_at.desc,id.desc")
        let decoder = JSONDecoder()
        let plans = try decoder.decode([PlanRow].self, from: await planData).map { try $0.workout() }
        let records = try decoder.decode([SessionRow].self, from: await sessionData).map { try $0.record() }
        return (plans, records)
    }

    private func queuePlanChanges(from previous: [Workout]) {
        let oldByID = Dictionary(uniqueKeysWithValues: previous.enumerated().map { ($0.element.id, $0.offset) })
        for old in previous where !plans.contains(where: { $0.id == old.id }) {
            pending.append(Mutation(path: "/rest/v1/workout_plans?id=eq.\(old.id.uuidString)", method: "DELETE"))
        }
        for (index, plan) in plans.enumerated() {
            if let oldIndex = oldByID[plan.id], oldIndex == index, previous[oldIndex] == plan { continue }
            var fields = plan.cloudFields
            fields["id"] = plan.id.uuidString
            fields["sort_order"] = index
            pending.append(Mutation(path: "/rest/v1/workout_plans", method: "POST", fields: fields,
                                    prefer: "resolution=merge-duplicates"))
        }
        flush()
    }

    private func queueRecordChanges(from previous: [WorkoutRecord]) {
        let oldByID = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
        for old in previous where !records.contains(where: { $0.id == old.id }) {
            pending.append(Mutation(path: "/rest/v1/workout_sessions?id=eq.\(old.id.uuidString)", method: "DELETE"))
        }
        for record in records {
            if let old = oldByID[record.id] {
                if old.note != record.note {
                    pending.append(Mutation(path: "/rest/v1/workout_sessions?id=eq.\(record.id.uuidString)",
                                            method: "PATCH", fields: ["note": record.note]))
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
                pending.append(Mutation(path: "/rest/v1/workout_sessions", method: "POST", fields: fields,
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
