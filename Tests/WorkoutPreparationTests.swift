import XCTest
@testable import MYMS

final class WorkoutPreparationTests: XCTestCase {
    @MainActor func testUnselectedDefaultWorkoutCannotStartEvenWhenMeasurementIsReady() {
        let coach = Coach()
        defer { coach.stopConnection() }
        XCTAssertNil(coach.selectedWorkoutID)
        XCTAssertFalse(coach.hasSelectedWorkout)
        coach.setSimulation(true)
        coach.gesture(4)
        XCTAssertEqual(coach.phase, .ready, "Internal default workout must not act as a selected plan")
    }

    @MainActor func testSelectedPlanNeedsRealMeasurementAndShowsReason() {
        let coach = Coach()
        defer { coach.stopConnection() }
        let plan = Workout()
        coach.recordingAvailable = true
        coach.select(plan)
        XCTAssertEqual(coach.selectedWorkoutID, plan.id)
        XCTAssertTrue(coach.hasSelectedWorkout)
        XCTAssertFalse(coach.canStartWorkout)
        XCTAssertTrue(coach.startBlockReason?.contains("센서") == true)
        coach.gesture(4)
        XCTAssertEqual(coach.phase, .ready)
    }

    @MainActor func testExplicitSelectionAndPreparedMeasurementCanStart() {
        let coach = Coach()
        defer { coach.stopConnection() }
        let plan = Workout()
        coach.select(plan)
        coach.setSimulation(true)
        XCTAssertTrue(coach.canStartWorkout)
        XCTAssertNil(coach.startBlockReason)
        coach.gesture(4)
        XCTAssertEqual(coach.phase, .calibrating)
        coach.reconcilePlans([])
        XCTAssertEqual(coach.selectedWorkoutID, plan.id, "Active workout keeps its snapshot")
    }

    @MainActor func testEditingAndDeletingSelectedIdlePlanUpdatesSelection() {
        let coach = Coach()
        defer { coach.stopConnection() }
        var plan = Workout()
        coach.select(plan)
        plan.target = 15
        coach.reconcilePlans([plan])
        XCTAssertEqual(coach.workout.target, 15)
        coach.reconcilePlans([])
        XCTAssertNil(coach.selectedWorkoutID)
        XCTAssertFalse(coach.hasSelectedWorkout)
        coach.setSimulation(true)
        XCTAssertFalse(coach.canStartWorkout)
    }

    @MainActor func testRecoveryKeepsItsPlanEvenIfRemovedFromCurrentPlans() {
        let coach = Coach()
        defer { coach.stopConnection() }
        let plan = Workout()
        let now = Date()
        let progress = WorkoutProgress(id: UUID(), workout: plan, startedAt: now, elapsedSeconds: 5,
            reps: 1, set: 1, totalReps: 1, completedSets: 0, restSeconds: 0, phase: .training,
            measurementSource: "ToF 거리", environment: nil, updatedAt: now)
        coach.onCheckpoint = { _ in true }
        coach.onComplete = { _ in true }
        coach.offerRecovery(progress)
        XCTAssertTrue(coach.restoreRecovery())
        XCTAssertEqual(coach.selectedWorkoutID, plan.id)
        coach.reconcilePlans([])
        XCTAssertTrue(coach.hasSelectedWorkout)
        XCTAssertEqual(coach.phase, .paused)
        coach.finish()
        coach.reconcilePlans([])
        XCTAssertFalse(coach.hasSelectedWorkout)
        XCTAssertNotNil(coach.summary, "Plan removal must not erase the completed result")
    }
}
