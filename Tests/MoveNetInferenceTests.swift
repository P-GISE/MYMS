import XCTest
import UIKit
import AVFoundation
@testable import MYMS

final class MoveNetInferenceTests: XCTestCase {
    func testCameraCapabilities() throws {
        let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTrueDepthCamera], mediaType: .video, position: .unspecified).devices
        XCTAssertFalse(devices.isEmpty)
        let selected = try XCTUnwrap(WorkoutCameraDevice.preferredFront())
        let ultraWide = devices.first { $0.position == .front && $0.deviceType == .builtInUltraWideCamera }
        XCTAssertEqual(selected.position, .front, "Workout assistance must face the person viewing the screen")
        XCTAssertEqual(selected.deviceType, ultraWide == nil ? .builtInWideAngleCamera : .builtInUltraWideCamera)
        XCTAssertEqual(selected.videoZoomFactor, 1, "Use the lens's native widest view rather than digital zoom")
        for device in devices {
            print("MYMS camera: position=\(device.position.rawValue) type=\(device.deviceType.rawValue) zoom=\(device.minAvailableVideoZoomFactor)...\(device.maxAvailableVideoZoomFactor) fov=\(device.activeFormat.videoFieldOfView)")
        }
    }

    func testThunderDetectsReferencePerson() throws {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: "pose-person", withExtension: "jpeg"))
        let image = try XCTUnwrap(UIImage(contentsOfFile: url.path)?.cgImage)
        let model = try MoveNetPoseEstimator()
        let started = Date()
        let points = try model.predict(image)
        let joints = Set(points.map(\.joint))
        XCTAssertGreaterThanOrEqual(points.count, 12, "Reference full body must produce usable keypoints")
        for joint: PoseJoint in [.nose, .leftElbow, .rightElbow, .leftWrist, .rightWrist, .leftKnee, .rightKnee] {
            XCTAssertTrue(joints.contains(joint), "Missing \(joint)")
        }
        XCTAssertTrue(points.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
        print("MoveNet Thunder reference person: \(points.count)/17 points, \(Int(Date().timeIntervalSince(started) * 1000))ms")
    }

    func testBlankFrameDoesNotReusePreviousPose() throws {
        let model = try MoveNetPoseEstimator()
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: "pose-person", withExtension: "jpeg"))
        let person = try XCTUnwrap(UIImage(contentsOfFile: url.path)?.cgImage)
        XCTAssertGreaterThan(try model.predict(person).count, 0)
        let blank = UIGraphicsImageRenderer(size: CGSize(width: 640, height: 480)).image { renderer in
            UIColor.black.setFill()
            renderer.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
        }
        let points = try model.predict(XCTUnwrap(blank.cgImage))
        XCTAssertTrue(points.isEmpty, "Blank frame must clear the reference pose")
    }
}
