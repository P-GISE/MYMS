import XCTest
import Combine
@testable import MYMS

final class SimulationHistoryTests: XCTestCase {
    func testStatisticsSwitchSeparatesExerciseSimulationAndIMU() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 12))!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        func record(_ reps: Int, source: String?, date: Date) -> WorkoutRecord {
            var value = WorkoutRecord(workout: Workout(), reps: reps, sets: 0, seconds: 30, points: 0)
            value.measurementSource = source
            value.date = date
            return value
        }
        let records = [record(4, source: nil, date: now),
                       record(7, source: WorkoutRecord.simulationSource, date: now),
                       record(3, source: WorkoutRecord.simulationSource, date: yesterday),
                       record(99, source: "IMU 동작 테스트", date: now),
                       record(0, source: WorkoutRecord.simulationSource, date: now),
                       record(50, source: WorkoutRecord.simulationSource, date: now.addingTimeInterval(86400))]
        XCTAssertEqual(WorkoutStatistics.Source.exercise.records(from: records).map(\.id), [records[0].id])
        XCTAssertEqual(WorkoutStatistics.Source.simulation.records(from: records).map(\.id),
                       [records[1].id, records[2].id, records[4].id, records[5].id])
        XCTAssertTrue(WorkoutStatistics.Source.simulation.records(from: []).isEmpty)
        let real = WorkoutStatistics(records: records, now: now, calendar: calendar)
        XCTAssertEqual(real.week.reduce(0) { $0 + $1.reps }, 4)
        XCTAssertEqual(real.personalBest, 4)
        let demo = WorkoutStatistics(records: records, source: .simulation, now: now, calendar: calendar)
        XCTAssertEqual(demo.week.reduce(0) { $0 + $1.reps }, 10)
        XCTAssertEqual(demo.personalBest, 7)
        XCTAssertEqual(demo.streak, 2)
        let empty = WorkoutStatistics(records: [], source: .simulation, now: now, calendar: calendar)
        XCTAssertEqual(empty.week.count, 7)
        XCTAssertTrue(empty.week.allSatisfy { $0.reps == 0 })
        XCTAssertEqual(empty.streak, 0)
    }

    @MainActor func testEndingZeroRepSimulationSavesHistoryAcrossRestart() throws {
        let account = UUID()
        defer { try? WorkoutStore.deleteLocalData(for: account) }
        let store = WorkoutStore(accountID: account)
        let coach = Coach()
        defer { coach.stopConnection() }
        coach.onComplete = { store.complete($0) }
        coach.onDiscard = { store.discardProgress() }
        coach.select(Workout())
        coach.setSimulation(true)
        coach.gesture(4)
        coach.pause()
        coach.finish()
        XCTAssertEqual(coach.phase, .finished)
        XCTAssertEqual(store.records.count, 1, "Ended simulation must appear in history, even with no virtual reps")
        let reopened = WorkoutStore(accountID: account)
        XCTAssertEqual(reopened.records.count, 1)
        let saved = try XCTUnwrap(reopened.records.first)
        XCTAssertTrue(saved.isSimulation)
        XCTAssertTrue(saved.isLocalOnly)
        XCTAssertEqual(saved.reps, 0)
        XCTAssertEqual(saved.points, 0)
        XCTAssertEqual(coach.summary?.id, saved.id)
        coach.finish()
        XCTAssertTrue(store.complete(saved))
        XCTAssertEqual(store.records.count, 1)
    }

    @MainActor func testAutomaticTargetCompletionPersistsExactlyOneSimulation() async throws {
        let account = UUID()
        defer { try? WorkoutStore.deleteLocalData(for: account) }
        let store = WorkoutStore(accountID: account)
        let coach = Coach()
        defer { coach.stopConnection() }
        coach.onComplete = { store.complete($0) }
        var plan = Workout()
        plan.target = 1
        plan.sets = 1
        coach.select(plan)
        coach.setSimulation(true)
        let training = expectation(description: "Calibration finishes")
        let trainingObserver = coach.$phase.filter { $0 == .training }.first().sink { _ in training.fulfill() }
        defer { trainingObserver.cancel() }
        coach.gesture(4)
        await fulfillment(of: [training], timeout: 8)
        let finished = expectation(description: "Target completes and saves")
        let finishObserver = coach.$phase.filter { $0 == .finished }.first().sink { _ in finished.fulfill() }
        defer { finishObserver.cancel() }
        coach.simulateRep()
        await fulfillment(of: [finished], timeout: 5)
        XCTAssertEqual(store.records.count, 1)
        let saved = try XCTUnwrap(store.records.first)
        XCTAssertEqual(saved.reps, 1)
        XCTAssertEqual(saved.sets, 1)
        XCTAssertEqual(saved.points, 0)
        XCTAssertTrue(saved.isSimulation)
        XCTAssertNil(store.progress, "Simulation must not create an active recovery checkpoint")
        coach.finish()
        XCTAssertEqual(WorkoutStore(accountID: account).records.count, 1)
    }

    @MainActor func testFailedSaveRetriesWithSameCompletionID() throws {
        let account = UUID()
        defer { try? WorkoutStore.deleteLocalData(for: account) }
        let store = WorkoutStore(accountID: account)
        let coach = Coach()
        defer { coach.stopConnection() }
        var attempts: [UUID] = []
        coach.onComplete = { attempts.append($0.id); return store.complete($0) }
        coach.select(Workout())
        coach.setSimulation(true)
        coach.gesture(4)
        coach.pause()
        let url = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true).appendingPathComponent("MYMS").appendingPathComponent(account.uuidString + ".json")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        coach.finish()
        XCTAssertEqual(coach.phase, .paused)
        XCTAssertNotNil(coach.persistenceError)
        XCTAssertTrue(store.records.isEmpty)
        try FileManager.default.removeItem(at: url)
        XCTAssertTrue(coach.retryPersistence())
        XCTAssertEqual(coach.phase, .finished)
        XCTAssertNil(coach.persistenceError)
        XCTAssertEqual(attempts.count, 2)
        XCTAssertEqual(attempts.first, attempts.last)
        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(WorkoutStore(accountID: account).records.count, 1)
    }

    @MainActor func testSimulationSurvivesCloudRefreshAndDoesNotAffectStatistics() {
        var demo = WorkoutRecord(workout: Workout(), reps: 10, sets: 1, seconds: 30, points: 0)
        demo.measurementSource = WorkoutRecord.simulationSource
        let merged = WorkoutStore.mergeRemoteRecords([], local: [demo])
        XCTAssertEqual(merged.map(\.id), [demo.id])
        let repeated = WorkoutStore.mergeRemoteRecords([demo], local: [demo])
        XCTAssertEqual(repeated.count, 1)
        let stats = WorkoutStatistics(records: merged)
        XCTAssertEqual(stats.personalBest, 0)
        XCTAssertEqual(stats.streak, 0)
        XCTAssertTrue(stats.week.allSatisfy { $0.reps == 0 })
    }

    @MainActor func testSimulationCannotEarnOrConsumeDailyPoints() throws {
        let account = UUID()
        defer { try? WorkoutStore.deleteLocalData(for: account) }
        let store = WorkoutStore(accountID: account)
        var demo = WorkoutRecord(workout: Workout(), reps: 10, sets: 1, seconds: 30, points: 999)
        demo.measurementSource = WorkoutRecord.simulationSource
        XCTAssertTrue(store.complete(demo))
        XCTAssertEqual(store.points, 0)
        let real = WorkoutRecord(workout: Workout(), reps: 10, sets: 1, seconds: 30, points: 300)
        XCTAssertTrue(store.complete(real))
        XCTAssertEqual(store.points, 300)
    }
}
