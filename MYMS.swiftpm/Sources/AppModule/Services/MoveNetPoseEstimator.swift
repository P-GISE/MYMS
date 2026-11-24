import Foundation
import CoreGraphics
import TensorFlowLite

enum MoveNetError: LocalizedError {
    case missingModel, unsupportedTensor
    var errorDescription: String? {
        switch self {
        case .missingModel: return "MoveNet Thunder 모델을 찾을 수 없습니다. 앱을 다시 설치해 주세요."
        case .unsupportedTensor: return "MoveNet 모델의 입출력 형식이 올바르지 않습니다."
        }
    }
}

/// Owned and called only by the camera's serial processing queue.
final class MoveNetPoseEstimator {
    private let interpreter: Interpreter
    private let inputType: Tensor.DataType
    private let inputSize: Int

    init() throws {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "movenet_thunder", withExtension: "tflite", subdirectory: "PoseResources")
                ?? bundle.url(forResource: "movenet_thunder", withExtension: "tflite") else { throw MoveNetError.missingModel }
        var options = Interpreter.Options()
        options.threadCount = 4
        interpreter = try Interpreter(modelPath: url.path, options: options)
        try interpreter.allocateTensors()
        let input = try interpreter.input(at: 0)
        let output = try interpreter.output(at: 0)
        guard input.shape.dimensions == [1, 256, 256, 3],
              [.uInt8, .int32, .float32].contains(input.dataType),
              output.shape.dimensions == [1, 1, 17, 3], output.dataType == .float32 else { throw MoveNetError.unsupportedTensor }
        inputType = input.dataType
        inputSize = input.shape.dimensions[1]
    }

    func predict(_ image: CGImage) throws -> [PoseLandmark] {
        let rgb = try PoseImageInput.rgbData(image, size: inputSize)
        let data: Data
        switch inputType {
        case .uInt8: data = rgb
        case .int32: data = rgb.map(Int32.init).withUnsafeBytes { Data($0) }
        case .float32: data = rgb.map(Float.init).withUnsafeBytes { Data($0) }
        default: throw MoveNetError.unsupportedTensor
        }
        try interpreter.copy(data, toInputAt: 0)
        try interpreter.invoke()
        let output = try interpreter.output(at: 0)
        guard output.data.count == 51 * MemoryLayout<Float>.size else { throw MoveNetError.unsupportedTensor }
        let values: [Float] = output.data.withUnsafeBytes { bytes in
            (0..<51).map { bytes.loadUnaligned(fromByteOffset: $0 * 4, as: Float.self) }
        }
        return try PoseLetterbox(width: Double(image.width), height: Double(image.height)).decode(values)
    }
}
