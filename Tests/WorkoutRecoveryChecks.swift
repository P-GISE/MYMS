import Foundation

@main
struct WorkoutRecoveryChecks {
    @MainActor static func main() throws {
        let account = UUID()
        let otherAccount = UUID()
        defer {
            try? WorkoutStore.deleteLocalData(for: account)
            try? WorkoutStore.deleteLocalData(for: otherAccount)
        }
        let url = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                              appropriateFor: nil, create: true)
            .appendingPathComponent("MYMS").appendingPathComponent(account.uuidString + ".json")
        let plan = Workout()
        let session = UUID()
        let now = Date()
        let environment = SensorEnvironment(brightnessRaw: 230, brightnessReference: 200,
                                            inclineDegrees: 2, measuredAt: now,
                                            equipment: .available, place: .outdoors, footwear: .runningShoes)
        func checkpoint(_ phase: WorkoutProgress.Phase, id: UUID? = nil,
                        elapsed: Int = 12, workout: Workout? = nil, startedAt: Date? = nil,
                        source: String = "IMU 동작 테스트") -> WorkoutProgress {
            let resting = phase == .resting
            return WorkoutProgress(id: id ?? session, workout: workout ?? plan, startedAt: startedAt ?? now,
                                   elapsedSeconds: elapsed, reps: resting ? plan.target : 2, set: 1,
                                   totalReps: resting ? plan.target : 2, completedSets: resting ? 1 : 0,
                                   restSeconds: resting ? 15 : 0, phase: phase,
                                   measurementSource: source, environment: environment, updatedAt: now)
        }
        func record(id: UUID? = nil, points: Int = 10) -> WorkoutRecord {
            WorkoutRecord(id: id ?? session, workout: plan, reps: 2, sets: 0, seconds: 30, points: points,
                          environment: environment, measurementSource: "IMU 동작 테스트")
        }
        let store = WorkoutStore(token: nil, accountID: account)
        for phase: WorkoutProgress.Phase in [.calibrating, .training, .paused, .resting] {
            assert(store.updateProgress(checkpoint(phase)))
            let reopened = WorkoutStore(token: nil, accountID: account)
            assert(reopened.loaded && reopened.progress?.id == session)
            assert(reopened.progress?.phase == phase && reopened.progress?.elapsedSeconds == 12)
            assert(reopened.progress?.environment?.brightnessRaw == 230)
            assert(reopened.progress?.environment?.place == .outdoors)
            assert(store.discardProgress())
        }
        assert(store.updateProgress(checkpoint(.training)))
        let isolated = WorkoutStore(token: nil, accountID: otherAccount)
        assert(isolated.progress == nil && isolated.records.isEmpty)
        let beforeInvalid = try Data(contentsOf: url)
        assert(!store.updateProgress(checkpoint(.training, elapsed: -1)))
        assert(!store.updateProgress(checkpoint(.training, id: UUID())))
        assert(!store.updateProgress(checkpoint(.training, elapsed: 11)))
        assert(!store.updateProgress(checkpoint(.training, workout: Workout())))
        assert(!store.updateProgress(checkpoint(.training, startedAt: now.addingTimeInterval(-1))))
        assert(!store.updateProgress(checkpoint(.training, source: "ToF 거리")))
        assert(!store.complete(record(id: UUID())))
        var invalidRecord = record()
        invalidRecord.workout = Workout()
        assert(!store.complete(invalidRecord))
        invalidRecord = record()
        invalidRecord.measurementSource = "ToF 거리"
        assert(!store.complete(invalidRecord))
        invalidRecord = record()
        invalidRecord.reps = 1
        assert(!store.complete(invalidRecord))
        invalidRecord = record()
        invalidRecord.seconds = 11
        assert(!store.complete(invalidRecord))
        invalidRecord = record()
        invalidRecord.reps = plan.target * plan.sets + 1
        assert(!store.complete(invalidRecord))
        invalidRecord = record()
        invalidRecord.sets = 1
        assert(!store.complete(invalidRecord))
        let afterInvalid = try Data(contentsOf: url)
        assert(afterInvalid == beforeInvalid)

        assert(store.updateProgress(checkpoint(.resting)))
        let afterRest = try Data(contentsOf: url)
        assert(!store.updateProgress(checkpoint(.training)))
        assert(!store.complete(record()))
        let afterStale = try Data(contentsOf: url)
        assert(afterStale == afterRest)
        assert(store.discardProgress())
        assert(store.updateProgress(checkpoint(.training)))

        // An occupied destination forces the real atomic writer to fail, without a mock store.
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        assert(!store.complete(record()))
        assert(store.records.isEmpty && store.points == 0 && store.progress?.id == session)
        assert(store.localError != nil)
        assert(!store.discardProgress() && store.progress?.id == session)
        assert(!store.updateProgress(checkpoint(.paused, elapsed: 30)))
        assert(store.progress?.elapsedSeconds == 12)
        try FileManager.default.removeItem(at: url)
        try beforeInvalid.write(to: url, options: .atomic)
        assert(store.updateProgress(checkpoint(.paused, elapsed: 30)))
        assert(store.complete(record()))
        let finished = WorkoutStore(token: nil, accountID: account)
        assert(finished.progress == nil && finished.records.count == 1 && finished.points == 10)
        let afterComplete = try Data(contentsOf: url)
        assert(finished.complete(record()))
        assert(finished.records.count == 1 && finished.points == 10)
        let afterDuplicate = try Data(contentsOf: url)
        assert(afterDuplicate == afterComplete)
        assert(!finished.updateProgress(checkpoint(.training)))
        finished.records.removeAll()
        let afterDelete = WorkoutStore(token: nil, accountID: account)
        assert(afterDelete.complete(record()) && afterDelete.records.isEmpty && afterDelete.points == 0)
        assert(!afterDelete.updateProgress(checkpoint(.paused)))

        // Old snapshots have neither a progress field nor a completion ledger.
        let legacyRecord = record(id: UUID(), points: 290)
        let legacy: [String: Any] = ["plans": [], "pending": [],
                                   "records": try JSONSerialization.jsonObject(with: JSONEncoder().encode([legacyRecord]))]
        try JSONSerialization.data(withJSONObject: legacy).write(to: url, options: .atomic)
        let migrated = WorkoutStore(token: nil, accountID: account)
        assert(migrated.loaded && migrated.progress == nil && migrated.points == 290)
        assert(migrated.complete(record(id: UUID(), points: 50)))
        assert(migrated.points == 300)
        migrated.records.removeAll()
        let migratedAgain = WorkoutStore(token: nil, accountID: account)
        assert(migratedAgain.complete(legacyRecord) && migratedAgain.records.isEmpty)
        assert(migratedAgain.updateProgress(checkpoint(.training, id: UUID())))
        assert(migratedAgain.discardProgress())
        assert(WorkoutStore(token: nil, accountID: account).progress == nil)

        var malformed = legacy
        malformed["progress"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(checkpoint(.training, elapsed: -1)))
        let malformedData = try JSONSerialization.data(withJSONObject: malformed)
        try malformedData.write(to: url, options: .atomic)
        let corrupt = WorkoutStore(token: nil, accountID: account)
        assert(!corrupt.loaded && corrupt.localError != nil)
        assert(!corrupt.updateProgress(checkpoint(.training)) && !corrupt.complete(record()))
        corrupt.retry()
        let preserved = try Data(contentsOf: url)
        assert(preserved == malformedData)
        print("PASS: phase reconstruction, account isolation, invalid checkpoint rejection, atomic rollback/retry, duplicate completion after deletion, daily cap, legacy migration, discard, corrupt file protection")
    }
}
