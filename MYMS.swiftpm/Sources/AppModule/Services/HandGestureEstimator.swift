import Foundation
import UIKit
import MediaPipeTasksVision

enum HandTrackingError: LocalizedError {
    case missingModel, invalidTimestamp
    var errorDescription: String? {
        switch self {
        case .missingModel: return "손 추적 모델을 찾을 수 없습니다. 앱을 다시 설치해 주세요."
        case .invalidTimestamp: return "손 추적 영상의 시간 순서가 올바르지 않습니다."
        }
    }
}

/// Serialize calls on the same camera queue as Thunder; no camera images are retained.
final class HandGestureEstimator {
    private let recognizer: GestureRecognizer
    private let video: Bool
    private var lastTimestamp = -1

    init(video: Bool = true) throws {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "gesture_recognizer", withExtension: "task", subdirectory: "PoseResources")
                ?? bundle.url(forResource: "gesture_recognizer", withExtension: "task") else { throw HandTrackingError.missingModel }
        let options = GestureRecognizerOptions()
        options.baseOptions.modelAssetPath = url.path
        options.runningMode = video ? .video : .image
        options.numHands = 2
        options.minHandDetectionConfidence = 0.5
        options.minHandPresenceConfidence = 0.5
        options.minTrackingConfidence = 0.5
        recognizer = try GestureRecognizer(options: options)
        self.video = video
    }

    func predict(_ image: CGImage, timestampMilliseconds: Int = 0) throws -> [TrackedHand] {
        let input = try MPImage(uiImage: UIImage(cgImage: image))
        let result: GestureRecognizerResult
        if video {
            guard timestampMilliseconds >= 0, timestampMilliseconds > lastTimestamp else { throw HandTrackingError.invalidTimestamp }
            lastTimestamp = timestampMilliseconds
            result = try recognizer.recognize(videoFrame: input, timestampInMilliseconds: timestampMilliseconds)
        } else {
            result = try recognizer.recognize(image: input)
        }
        return result.landmarks.enumerated().compactMap { index, landmarks in
            guard landmarks.count == 21 else { return nil }
            let points = landmarks.enumerated().map {
                HandLandmark(index: $0.offset, x: Double($0.element.x), y: Double($0.element.y))
            }
            let category = index < result.gestures.count
                ? result.gestures[index].max(by: { $0.score < $1.score }) : nil
            return TrackedHand(points: points, category: category?.categoryName, score: category?.score ?? 0)
        }
    }
}
