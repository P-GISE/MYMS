import Foundation

@main
struct LocalHistoryChecks {
    @MainActor static func main() throws {
        try verifyLocalHistoryAndStatistics()
    }
}

@MainActor
func verifyLocalHistoryAndStatistics() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.firstWeekday = 2
    let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 12))!
    let accountID = UUID()
    let otherID = UUID()
    defer {
        try? WorkoutStore.deleteLocalData(for: accountID)
        try? WorkoutStore.deleteLocalData(for: otherID)
    }
    let store = WorkoutStore(token: nil, accountID: accountID)
    assert(store.loaded && store.localError == nil)
    let plan = Workout()
    store.plans = [plan]
    let environment = SensorEnvironment(brightnessRaw: 250, brightnessReference: 200, inclineDegrees: 1.2,
                                        measuredAt: now, equipment: .available, place: .outdoors, footwear: .runningShoes)
    func record(days: Int, reps: Int, source: String = "ToF 거리") -> WorkoutRecord {
        WorkoutRecord(workout: plan, date: calendar.date(byAdding: .day, value: days, to: now)!,
                      reps: reps, sets: 1, seconds: 30, points: 0, environment: environment, measurementSource: source)
    }
    store.records = [record(days: 0, reps: 10), record(days: -1, reps: 20), record(days: -2, reps: 5),
                     record(days: -5, reps: 30), record(days: -9, reps: 40), record(days: 0, reps: 99, source: "IMU 동작 테스트")]
    assert(store.localError == nil)
    let restored = WorkoutStore(token: nil, accountID: accountID)
    assert(restored.records.count == 6 && restored.plans == [plan])
    assert(restored.records.first?.environment?.brightnessRaw == 250)
    assert(restored.records.first?.environment?.inclineDegrees == 1.2)
    assert(restored.records.first?.environment?.equipment == .available)
    assert(restored.records.first?.environment?.place == .outdoors)
    assert(restored.records.first?.environment?.footwear == .runningShoes)
    assert(restored.records.last?.measurementSource == "IMU 동작 테스트")
    let isolated = WorkoutStore(token: nil, accountID: otherID)
    assert(isolated.records.isEmpty && isolated.plans.isEmpty)
    let stats = WorkoutStatistics(records: restored.records, now: now, calendar: calendar)
    assert(stats.week.reduce(0) { $0 + $1.reps } == 65)
    assert(stats.streak == 3 && stats.personalBest == 40)
    restored.records.removeAll { calendar.isDate($0.date, inSameDayAs: now) }
    let afterDelete = WorkoutStore(token: nil, accountID: accountID)
    assert(afterDelete.records.count == 4)
    let yesterday = WorkoutStatistics(records: afterDelete.records, now: now, calendar: calendar)
    assert(yesterday.streak == 2)
    let empty = WorkoutStatistics(records: [], now: now, calendar: calendar)
    assert(empty.streak == 0 && empty.personalBest == 0 && empty.week.allSatisfy { $0.reps == 0 })
    print("PASS: restart persistence, environment/source roundtrip, account isolation, deletion, week totals, streak, PR, test exclusion")
}
