import Foundation

@main
struct StoredDataSecurityChecks {
    @MainActor static func main() throws {
        let account = UUID()
        defer { try? WorkoutStore.deleteLocalData(for: account) }
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true).appendingPathComponent("MYMS")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent(account.uuidString + ".json")
        var invalidPlan = Workout()
        invalidPlan.target = -1
        let plans = try JSONSerialization.jsonObject(with: JSONEncoder().encode([invalidPlan]))
        let original = try JSONSerialization.data(withJSONObject: ["plans": plans, "records": [], "pending": []])
        try original.write(to: url, options: .atomic)
        let store = WorkoutStore(accountID: account)
        precondition(!store.loaded && store.localError != nil, "Invalid persisted workout was accepted")
        let preserved = try Data(contentsOf: url)
        precondition(preserved == original, "Invalid original must remain recoverable")
        var record = WorkoutRecord(workout: Workout(), reps: 1, sets: 0, seconds: 1, points: Int.max)
        let records = try JSONSerialization.jsonObject(with: JSONEncoder().encode([record, record]))
        try JSONSerialization.data(withJSONObject: ["plans": [], "records": records, "pending": []]).write(to: url, options: .atomic)
        let corruptPoints = WorkoutStore(accountID: account)
        precondition(!corruptPoints.loaded, "Unsafe point totals accepted")
        try FileManager.default.removeItem(at: url)
        let safe = WorkoutStore(accountID: account)
        safe.plans = [invalidPlan]
        precondition(safe.plans.isEmpty && safe.localError != nil, "Invalid plan assignment must roll back")
        record.points = 1
        record.reps = Int.max
        safe.records = [record]
        precondition(safe.records.isEmpty, "Unsafe rep totals accepted")
        let futureRecord = WorkoutRecord(workout: Workout(), date: Date.distantFuture.addingTimeInterval(60),
            reps: 1, sets: 0, seconds: 1, points: 1)
        precondition(!safe.complete(futureRecord), "Completion must not write a snapshot that cannot be reopened")
        let other = UUID()
        let scoped = try WorkoutStore.ownerScopedRequest("/rest/v1/workout_sessions?id=eq.test&user_id=eq.\(other)", method: "DELETE", body: nil, accountID: account)
        let ownerFilters = URLComponents(string: scoped.path)?.queryItems?.filter { $0.name == "user_id" }
        precondition(ownerFilters?.count == 1 && ownerFilters?.first?.value == "eq." + account.uuidString)
        let insert = try WorkoutStore.ownerScopedRequest("/rest/v1/workout_plans", method: "POST", body: ["user_id": other.uuidString], accountID: account)
        precondition(insert.body?["user_id"] as? String == account.uuidString)
        do {
            _ = try WorkoutStore.ownerScopedRequest("/rest/v1/rpc/delete_my_account", method: "POST", body: [:], accountID: account)
            preconditionFailure("Queued mutations must not call unrelated APIs")
        } catch {}
        print("Stored-data security checks passed: invalid plans/records rejected, original preserved, edits rolled back")
    }
}
