import Foundation
import Combine

@MainActor
final class WorkoutStore: ObservableObject {
    @Published var plans: [Workout] = [] {
        didSet { if loaded && !loading { changedPlans(from: oldValue) } }
    }
    @Published var records: [WorkoutRecord] = [] {
        didSet { if loaded && !loading { changedRecords(from: oldValue) } }
    }
    @Published private(set) var progress: WorkoutProgress?
    @Published private(set) var loaded = false
    @Published private(set) var syncError: String?
    @Published private(set) var localError: String?
    @Published private(set) var syncing = false

    private let token: String?
    private let accounts: Accounts?
    private let accountID: UUID
    private var loading = false
    private var revision = 0
    private var pending: [Mutation] = []
    private var unreadableSnapshot = false
    private var completedSessionIDs: Set<UUID> = []

    private struct Mutation: Codable {
        let path: String
        let method: String
        let body: Data?
        let prefer: String?

        init(path: String, method: String, body: [String: Any]?, prefer: String? = nil) throws {
            self.path = path
            self.method = method
            self.body = try body.map { try JSONSerialization.data(withJSONObject: $0) }
            self.prefer = prefer
        }
    }

    private struct Snapshot: Codable {
        let plans: [Workout]
        let records: [WorkoutRecord]
        let pending: [Mutation]
        let progress: WorkoutProgress?
        let completedSessionIDs: Set<UUID>

        init(plans: [Workout], records: [WorkoutRecord], pending: [Mutation],
             progress: WorkoutProgress?, completedSessionIDs: Set<UUID>) {
            self.plans = plans
            self.records = records
            self.pending = pending
            self.progress = progress
            self.completedSessionIDs = completedSessionIDs
        }

        enum CodingKeys: String, CodingKey { case plans, records, pending, progress, completedSessionIDs }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            plans = try values.decode([Workout].self, forKey: .plans)
            records = try values.decode([WorkoutRecord].self, forKey: .records)
            guard plans.allSatisfy(\.isValid), records.allSatisfy(\.hasSafeStoredValues),
                  Set(plans.map(\.id)).count == plans.count,
                  Set(records.map(\.id)).count == records.count else {
                throw DecodingError.dataCorruptedError(forKey: .records, in: values, debugDescription: "Invalid stored workout data")
            }
            pending = try values.decodeIfPresent([Mutation].self, forKey: .pending) ?? []
            progress = try values.decodeIfPresent(WorkoutProgress.self, forKey: .progress)
            completedSessionIDs = (try values.decodeIfPresent(Set<UUID>.self, forKey: .completedSessionIDs) ?? [])
                .union(records.map(\.id))
            if let progress, !progress.isValid {
                throw DecodingError.dataCorruptedError(forKey: .progress, in: values,
                                                       debugDescription: "Invalid workout checkpoint")
            }
        }
    }

    var points: Int { records.reduce(0) { $0 + $1.points } }

    init(token: String? = nil, accountID: UUID, accounts: Accounts? = nil) {
        self.token = token
        self.accounts = accounts
        self.accountID = accountID
        do {
            let url = try Self.snapshotURL(for: accountID)
            if FileManager.default.fileExists(atPath: url.path) {
                #if os(iOS)
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
                #endif
                let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: url))
                plans = snapshot.plans
                records = snapshot.records
                pending = snapshot.pending
                completedSessionIDs = snapshot.completedSessionIDs
                progress = snapshot.progress.flatMap { completedSessionIDs.contains($0.id) ? nil : $0 }
            }
            loaded = true
        } catch {
            unreadableSnapshot = true
            localError = "로컬 기록을 열지 못했습니다. 원본 파일은 보존됩니다: " + error.localizedDescription
        }
    }

    private var cloudEnabled: Bool {
        if let accounts { return accounts.current?.id == accountID && !accounts.isLocalMode }
        return token != nil
    }

    private func request(_ path: String, method: String = "GET", body: [String: Any]? = nil,
                         prefer: String? = nil) async throws -> Data {
        let scoped = try Self.ownerScopedRequest(path, method: method, body: body, accountID: accountID)
        if let accounts {
            guard accounts.current?.id == accountID, !accounts.isLocalMode else {
                throw URLError(.userAuthenticationRequired)
            }
            let data = try await accounts.request(scoped.path, method: method, body: scoped.body, prefer: prefer)
            guard accounts.current?.id == accountID, !accounts.isLocalMode else {
                throw URLError(.userAuthenticationRequired)
            }
            return data
        }
        return try await MYMSCloud.request(scoped.path, method: method, token: token, body: scoped.body, prefer: prefer)
    }

    static func ownerScopedRequest(_ path: String, method: String, body: [String: Any]?, accountID: UUID) throws -> (path: String, body: [String: Any]?) {
        guard var parts = URLComponents(string: path), parts.scheme == nil, parts.host == nil, parts.fragment == nil,
              ["/rest/v1/workout_plans", "/rest/v1/workout_sessions"].contains(parts.path),
              ["GET", "POST", "PATCH", "DELETE"].contains(method) else { throw URLError(.badURL) }
        var query = parts.queryItems ?? []
        query.removeAll { $0.name == "user_id" }
        query.append(URLQueryItem(name: "user_id", value: "eq." + accountID.uuidString))
        parts.queryItems = query
        var fields = body
        if method == "POST" { fields?["user_id"] = accountID.uuidString }
        else if fields?["user_id"] != nil { throw URLError(.badURL) }
        guard let result = parts.string else { throw URLError(.badURL) }
        return (result, fields)
    }

    static func namespace(for accountID: UUID) -> String {
        "myms.account.\(accountID.uuidString)."
    }

    private static func snapshotURL(for accountID: UUID) throws -> URL {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
            .appendingPathComponent("MYMS", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent(accountID.uuidString + ".json")
    }

    static func deleteLocalData(for accountID: UUID) throws {
        let url = try snapshotURL(for: accountID)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    @discardableResult
    private func persist() -> Bool {
        guard !unreadableSnapshot else { return false }
        do {
            let data = try JSONEncoder().encode(snapshot())
            #if os(iOS)
            try data.write(to: Self.snapshotURL(for: accountID), options: [.atomic, .completeFileProtection])
            #else
            try data.write(to: Self.snapshotURL(for: accountID), options: .atomic)
            #endif
            localError = nil
            return true
        } catch {
            localError = "기기 저장 실패 — 앱을 닫기 전에 다시 시도하세요: " + error.localizedDescription
            return false
        }
    }

    private func snapshot(plans previousPlans: [Workout]? = nil, records previousRecords: [WorkoutRecord]? = nil) -> Snapshot {
        Snapshot(plans: previousPlans ?? plans, records: previousRecords ?? records, pending: pending,
                 progress: progress, completedSessionIDs: completedSessionIDs)
    }

    private func restore(_ snapshot: Snapshot) {
        loading = true
        plans = snapshot.plans
        records = snapshot.records
        progress = snapshot.progress
        pending = snapshot.pending
        completedSessionIDs = snapshot.completedSessionIDs
        loading = false
    }

    // Checkpoints, completion IDs and queued uploads commit in one atomic file write.
    @discardableResult
    private func transaction(previous: Snapshot? = nil, changesHistory: Bool = true,
                             _ change: () throws -> Void) -> Bool {
        guard loaded, !unreadableSnapshot else { return false }
        let before = previous ?? snapshot()
        loading = true
        do {
            try change()
            loading = false
            guard persist() else { restore(before); return false }
            if changesHistory {
                revision += 1
                if cloudEnabled && !pending.isEmpty { Task { await load() } }
            }
            return true
        } catch {
            restore(before)
            localError = "변경 내용을 저장하지 못했습니다: " + error.localizedDescription
            return false
        }
    }

    @discardableResult
    func updateProgress(_ value: WorkoutProgress) -> Bool {
        guard value.isValid, !completedSessionIDs.contains(value.id),
              progress == nil || progress?.id == value.id else {
            localError = "진행 중인 운동과 저장하려는 운동이 일치하지 않거나 잘못된 기록입니다."
            return false
        }
        if let current = progress {
            guard value.workout == current.workout, value.startedAt == current.startedAt,
                  value.measurementSource == current.measurementSource,
                  value.totalReps >= current.totalReps, value.completedSets >= current.completedSets,
                  value.set >= current.set, value.elapsedSeconds >= current.elapsedSeconds else {
                localError = "이전 진행 상태로 덮어쓸 수 없습니다. 최신 운동 기록을 다시 불러오세요."
                return false
            }
        }
        return transaction(changesHistory: false) { progress = value }
    }

    @discardableResult
    func discardProgress() -> Bool {
        transaction(changesHistory: false) { progress = nil }
    }

    @discardableResult
    func complete(_ record: WorkoutRecord) -> Bool {
        guard loaded, !unreadableSnapshot else { return false }
        if completedSessionIDs.contains(record.id) {
            if progress?.id == record.id { return transaction(changesHistory: false) { progress = nil } }
            return true
        }
        var boundedRecord = record
        boundedRecord.points = min(record.points, 300)
        guard boundedRecord.hasSafeStoredValues,
              progress == nil || progress?.id == record.id,
              (1...100).contains(record.workout.target), (1...10).contains(record.workout.sets),
              (5...300).contains(record.workout.rest),
              (0...record.workout.sets).contains(record.sets),
              record.reps >= record.sets * record.workout.target,
              record.reps <= record.workout.target * record.workout.sets,
              record.seconds >= 0, record.points >= 0 else {
            localError = "완료할 운동이 진행 중인 운동과 일치하지 않거나 잘못된 기록입니다."
            return false
        }
        if let current = progress {
            guard record.workout == current.workout, record.measurementSource == current.measurementSource,
                  record.reps >= current.totalReps, record.sets >= current.completedSets,
                  record.seconds >= current.elapsedSeconds else {
                localError = "완료 기록이 저장된 진행 상태보다 이전이거나 다른 운동입니다."
                return false
            }
        }
        return transaction {
            let previous = records
            var entry = record
            let earned = records.filter { Calendar.current.isDate($0.date, inSameDayAs: entry.date) }
                .reduce(0) { $0 + $1.points }
            entry.points = min(entry.points, max(0, 300 - earned))
            records.insert(entry, at: 0)
            completedSessionIDs.insert(entry.id)
            progress = nil
            try enqueueRecordChanges(from: previous)
        }
    }

    func load() async {
        guard loaded, !syncing, cloudEnabled, persist() else { return }
        syncing = true
        syncError = nil
        defer {
            syncing = false
            if !pending.isEmpty && syncError == nil && localError == nil {
                Task { await load() }
            }
        }
        do {
            while let next = pending.first {
                let body = try next.body.map { data -> [String: Any] in
                    guard let fields = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        throw URLError(.cannotDecodeContentData)
                    }
                    return fields
                }
                _ = try await request(next.path, method: next.method,
                                                body: body, prefer: next.prefer)
                let acknowledged = pending.removeFirst()
                guard persist() else { pending.insert(acknowledged, at: 0); return }
            }
            let startRevision = revision
            async let planData = request("/rest/v1/workout_plans?order=sort_order.asc,id.asc")
            async let sessionData = request("/rest/v1/workout_sessions?order=finished_at.desc,id.desc")
            let decoder = JSONDecoder()
            let remotePlans = try decoder.decode([PlanRow].self, from: await planData).map { try $0.workout() }
            let remoteRecords = try decoder.decode([SessionRow].self, from: await sessionData).map { try $0.record() }
            guard startRevision == revision, pending.isEmpty else { return }
            let localByID = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let beforeRefresh = snapshot()
            loading = true
            plans = remotePlans
            records = remoteRecords.map { remote in
                var record = remote
                record.environment = localByID[record.id]?.environment
                record.measurementSource = localByID[record.id]?.measurementSource
                return record
            } + records.filter { $0.measurementSource == "IMU 동작 테스트" }
            records.sort { $0.date > $1.date }
            completedSessionIDs.formUnion(records.map(\.id))
            loading = false
            if !persist() { restore(beforeRefresh) }
        } catch {
            syncError = "서버 동기화 실패 (기기 기록은 유지됩니다): " + error.localizedDescription
        }
    }

    func retry() {
        guard persist() else { return }
        Task { await load() }
    }

    private func changedPlans(from previous: [Workout]) {
        transaction(previous: snapshot(plans: previous)) {
            guard plans.allSatisfy(\.isValid), Set(plans.map(\.id)).count == plans.count else { throw URLError(.cannotDecodeContentData) }
            if cloudEnabled {
                let oldByID = Dictionary(previous.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
                for old in previous where !plans.contains(where: { $0.id == old.id }) {
                    pending.append(try Mutation(path: "/rest/v1/workout_plans?id=eq.\(old.id.uuidString)", method: "DELETE", body: nil))
                }
                for (index, plan) in plans.enumerated() {
                    if let oldIndex = oldByID[plan.id], oldIndex == index, previous[oldIndex] == plan { continue }
                    var fields = plan.cloudFields
                    fields["id"] = plan.id.uuidString
                    fields["sort_order"] = index
                    pending.append(try Mutation(path: "/rest/v1/workout_plans", method: "POST", body: fields,
                                                prefer: "resolution=merge-duplicates"))
                }
            }
        }
    }

    private func changedRecords(from previous: [WorkoutRecord]) {
        let before = snapshot(records: previous)
        transaction(previous: before) {
            guard records.allSatisfy(\.hasSafeStoredValues), Set(records.map(\.id)).count == records.count else { throw URLError(.cannotDecodeContentData) }
            completedSessionIDs.formUnion(records.map(\.id))
            try enqueueRecordChanges(from: previous)
        }
    }

    private func enqueueRecordChanges(from previous: [WorkoutRecord]) throws {
        if cloudEnabled {
            let oldByID = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for old in previous where old.measurementSource != "IMU 동작 테스트" && !records.contains(where: { $0.id == old.id }) {
                pending.append(try Mutation(path: "/rest/v1/workout_sessions?id=eq.\(old.id.uuidString)", method: "DELETE", body: nil))
            }
            for record in records where record.measurementSource != "IMU 동작 테스트" {
                if let old = oldByID[record.id] {
                    if old.note != record.note {
                        pending.append(try Mutation(path: "/rest/v1/workout_sessions?id=eq.\(record.id.uuidString)",
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
                    pending.append(try Mutation(path: "/rest/v1/workout_sessions", method: "POST", body: fields,
                                                prefer: "resolution=ignore-duplicates"))
                }
            }
        }
    }

    func save(_ record: WorkoutRecord) {
        complete(record)
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
            let result = Workout(id: id, exercise: exercise, level: level, target: target_reps,
                                 sets: target_sets, rest: rest_seconds)
            guard result.isValid else { throw URLError(.cannotDecodeContentData) }
            return result
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
            let result = WorkoutRecord(id: plan.id, workout: try plan.workout(), date: date, reps: valid_reps,
                                       sets: completed_sets, seconds: duration_seconds, note: note, points: points_earned)
            guard result.hasSafeStoredValues else { throw URLError(.cannotDecodeContentData) }
            return result
        }
    }
}
