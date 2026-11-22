import Foundation
import Combine

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
