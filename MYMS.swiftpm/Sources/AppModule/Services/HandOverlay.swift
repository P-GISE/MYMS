import UIKit

enum HandOverlay {
    static func draw(_ hands: [TrackedHand], in context: CGContext, size: CGSize) {
        context.saveGState()
        defer { context.restoreGState() }
        let radius = max(3, size.width / 160)
        for hand in hands {
            let points = Dictionary(uniqueKeysWithValues: hand.visiblePoints.map {
                ($0.index, CGPoint(x: $0.x * size.width, y: $0.y * size.height))
            })
            context.setStrokeColor(UIColor.systemCyan.cgColor)
            context.setLineWidth(max(2, radius * 0.65))
            context.setShadow(offset: .zero, blur: 3, color: UIColor.black.cgColor)
            for (a, b) in HandLandmark.connections {
                guard let start = points[a], let end = points[b] else { continue }
                context.move(to: start)
                context.addLine(to: end)
                context.strokePath()
            }
            context.setFillColor(UIColor.systemCyan.cgColor)
            for point in points.values {
                context.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
            }
        }
    }
}
