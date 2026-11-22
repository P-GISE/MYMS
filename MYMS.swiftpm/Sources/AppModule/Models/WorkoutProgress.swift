import Foundation

struct WorkoutProgress: Codable, Identifiable {
    enum Phase: String, Codable {
        case calibrating, training, paused, resting
    }

    let id: UUID
    let workout: Workout
    let startedAt: Date
    let elapsedSeconds: Int
    let reps: Int
    let set: Int
    let totalReps: Int
    let completedSets: Int
    let restSeconds: Int
    let phase: Phase
    let measurementSource: String
    let environment: SensorEnvironment?
    let updatedAt: Date

    var isValid: Bool {
        guard (1...100).contains(workout.target), (1...10).contains(workout.sets),
              (5...300).contains(workout.rest), (1...workout.sets).contains(set),
              (0..<workout.sets).contains(completedSets), (0..<(Int.max / 2)).contains(elapsedSeconds),
              (0...workout.rest).contains(restSeconds),
              ["ToF 거리", "IMU 동작 테스트"].contains(measurementSource),
              startedAt.timeIntervalSinceReferenceDate.isFinite,
              updatedAt.timeIntervalSinceReferenceDate.isFinite else { return false }
        if phase == .resting {
            return set < workout.sets && completedSets == set && reps == workout.target
                && totalReps == completedSets * workout.target
        }
        return completedSets == set - 1 && (0..<workout.target).contains(reps)
            && totalReps == completedSets * workout.target + reps
    }
}
