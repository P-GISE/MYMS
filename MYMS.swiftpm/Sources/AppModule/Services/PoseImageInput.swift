import Foundation
import CoreGraphics

enum PoseImageInput {
    static func rgbData(_ image: CGImage, size: Int) throws -> Data {
        guard size > 0, size <= 2048,
              let context = CGContext(data: nil, width: size, height: size,
                bitsPerComponent: 8, bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        else { throw PoseDecodeError.invalidTensor }
        let scale = Double(size) / Double(max(image.width, image.height))
        let width = Double(image.width) * scale, height = Double(image.height) * scale
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: (Double(size) - width) / 2,
            y: (Double(size) - height) / 2, width: width, height: height))
        guard let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { throw PoseDecodeError.invalidTensor }
        var rgb = Data(count: size * size * 3)
        rgb.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
            for pixel in 0..<(size * size) {
                bytes[pixel * 3] = pixels[pixel * 4]
                bytes[pixel * 3 + 1] = pixels[pixel * 4 + 1]
                bytes[pixel * 3 + 2] = pixels[pixel * 4 + 2]
            }
        }
        return rgb
    }
}
