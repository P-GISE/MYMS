import Foundation
import CoreGraphics

@main
struct PoseImageChecks {
    static func main() throws {
        let rgba: [UInt8] = [255,0,0,255, 0,255,0,255, 0,0,255,255, 255,255,255,255]
        let image = CGImage(width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: Data(rgba) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let rgb = try PoseImageInput.rgbData(image, size: 2)
        precondition(Array(rgb) == [255,0,0, 0,255,0, 0,0,255, 255,255,255], "RGB order or vertical orientation changed")
        let wide = CGImage(width: 2, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: image.bitmapInfo,
            provider: CGDataProvider(data: Data(rgba.prefix(8)) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let padded = Array(try PoseImageInput.rgbData(wide, size: 4))
        precondition(padded.count == 48)
        precondition(padded.prefix(12).allSatisfy { $0 == 0 } && padded.suffix(12).allSatisfy { $0 == 0 })
        precondition(padded[12] > 200 && padded[22] > 200, "Image content lost inside padding")
        print("Pose image checks passed: RGB order, orientation, letterbox padding")
    }
}
