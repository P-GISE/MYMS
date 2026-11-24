import Foundation

/// MoveNet's COCO ordering. Coordinates use the displayed image's top-left origin.
enum PoseJoint: Int, CaseIterable {
    case nose, leftEye, rightEye, leftEar, rightEar
    case leftShoulder, rightShoulder, leftElbow, rightElbow, leftWrist, rightWrist
    case leftHip, rightHip, leftKnee, rightKnee, leftAnkle, rightAnkle

    var title: String {
        ["얼굴", "왼눈", "오른눈", "왼귀", "오른귀", "왼어깨", "오른어깨",
         "왼팔꿈치", "오른팔꿈치", "왼손목", "오른손목", "왼골반", "오른골반",
         "왼무릎", "오른무릎", "왼발목", "오른발목"][rawValue]
    }

    static let connections: [(PoseJoint, PoseJoint)] = [
        (.leftEar, .leftEye), (.leftEye, .nose), (.nose, .rightEye), (.rightEye, .rightEar),
        (.leftShoulder, .rightShoulder), (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.leftShoulder, .leftHip), (.rightShoulder, .rightHip), (.leftHip, .rightHip),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle), (.rightHip, .rightKnee), (.rightKnee, .rightAnkle)
    ]
}

struct PoseLandmark {
    let joint: PoseJoint
    let x: Double
    let y: Double
    let score: Float
}

enum PoseDecodeError: Error { case invalidTensor }

struct PoseLetterbox {
    let width: Double
    let height: Double
    var side: Double { max(width, height) }
    var padX: Double { (side - width) / 2 }
    var padY: Double { (side - height) / 2 }

    func decode(_ values: [Float], threshold: Float = 0.25) throws -> [PoseLandmark] {
        guard values.count == 51, width.isFinite, height.isFinite, width > 0, height > 0,
              threshold.isFinite, (0...1).contains(threshold) else { throw PoseDecodeError.invalidTensor }
        return PoseJoint.allCases.compactMap { joint in
            let index = joint.rawValue * 3
            let y = Double(values[index]), x = Double(values[index + 1]), score = values[index + 2]
            guard x.isFinite, y.isFinite, score.isFinite, (0...1).contains(x), (0...1).contains(y),
                  score >= threshold, score <= 1 else { return nil }
            let imageX = (x * side - padX) / width
            let imageY = (y * side - padY) / height
            guard (0...1).contains(imageX), (0...1).contains(imageY) else { return nil }
            return PoseLandmark(joint: joint, x: imageX, y: imageY, score: score)
        }
    }
}
