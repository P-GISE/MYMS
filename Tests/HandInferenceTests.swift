import XCTest
import UIKit
@testable import MYMS

final class HandInferenceTests: XCTestCase {
    private func image(_ name: String, extension suffix: String = "jpg") throws -> CGImage {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: suffix))
        return try XCTUnwrap(UIImage(contentsOfFile: url.path)?.cgImage)
    }

    func testOpenPalmsAndFistHave21PointsAndCorrectCategories() throws {
        let estimator = try HandGestureEstimator(video: false)
        let open = try estimator.predict(image("hand-open"))
        print("Open fixture: \(open.map { "\($0.visiblePoints.count) points \($0.category ?? "nil") \($0.score)" })")
        XCTAssertEqual(open.count, 2)
        XCTAssertTrue(open.allSatisfy { $0.points.count == 21 })
        XCTAssertTrue(open.contains { $0.gesture == .openPalm })
        let fist = try estimator.predict(image("hand-fist"))
        print("Fist fixture: \(fist.map { "\($0.visiblePoints.count) points \($0.category ?? "nil") \($0.score)" })")
        XCTAssertEqual(fist.count, 1)
        XCTAssertEqual(fist.first?.points.count, 21)
        XCTAssertEqual(fist.first?.gesture, .closedFist)
        let pose = try MoveNetPoseEstimator().predict(image("pose-person", extension: "jpeg"))
        XCTAssertGreaterThanOrEqual(pose.count, 12, "Hand runtime must not break Thunder")
    }

    func testVideoClearsHandsAndRejectsDuplicateTimestamp() throws {
        let estimator = try HandGestureEstimator()
        XCTAssertFalse(try estimator.predict(image("hand-fist"), timestampMilliseconds: 100).isEmpty)
        let blank = UIGraphicsImageRenderer(size: CGSize(width: 640, height: 480)).image { renderer in
            UIColor.black.setFill()
            renderer.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
        }
        let result = try estimator.predict(XCTUnwrap(blank.cgImage), timestampMilliseconds: 200)
        XCTAssertTrue(result.isEmpty, "No stale hand points or gesture after leaving frame")
        XCTAssertThrowsError(try estimator.predict(XCTUnwrap(blank.cgImage), timestampMilliseconds: 200))
    }
}
