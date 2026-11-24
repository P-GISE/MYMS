import Foundation

@main
struct PoseLandmarkChecks {
    static func main() throws {
        func check(_ condition: @autoclosure () throws -> Bool) rethrows {
            let result = try condition()
            precondition(result)
        }
        func output(x: Float, y: Float, score: Float = 0.9) -> [Float] {
            Array(repeating: [y, x, score], count: 17).flatMap { $0 }
        }
        let landscape = PoseLetterbox(width: 640, height: 480)
        let portrait = PoseLetterbox(width: 480, height: 640)
        let points = try landscape.decode(output(x: 0.25, y: 0.3125))
        precondition(points.count == 17)
        precondition(abs(points[0].x - 0.25) < 0.0001)
        precondition(abs(points[0].y - 0.25) < 0.0001)
        precondition(points[0].joint == .nose && points[7].joint == .leftElbow)
        precondition(points[9].joint == .leftWrist && points[16].joint == .rightAnkle)
        let tall = try portrait.decode(output(x: 0.3125, y: 0.25))
        precondition(abs(tall[0].x - 0.25) < 0.0001 && abs(tall[0].y - 0.25) < 0.0001)
        try check(try landscape.decode(output(x: 0.5, y: 0.5, score: 0.1)).isEmpty)
        try check(try landscape.decode(output(x: .nan, y: 0.5)).isEmpty)
        try check(try landscape.decode(output(x: 0.5, y: .infinity)).isEmpty)
        try check(try landscape.decode(output(x: 0.5, y: 0.05)).isEmpty)
        try check(try portrait.decode(output(x: 0.05, y: 0.5)).isEmpty)
        try check(try landscape.decode(output(x: 0.5, y: 0.5, score: 2)).isEmpty)
        do {
            _ = try landscape.decode([0, 0, 1])
            preconditionFailure("Invalid tensor accepted")
        } catch PoseDecodeError.invalidTensor {}
        precondition(PoseJoint.allCases.count == 17)
        precondition(PoseJoint.connections.allSatisfy { $0.0 != $0.1 })
        print("Pose landmark checks passed: ordering, letterbox, confidence, invalid input, no stale points")
    }
}
