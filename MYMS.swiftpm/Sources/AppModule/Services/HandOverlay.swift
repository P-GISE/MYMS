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
            if let wrist = points[0] {
                let title = "\(hand.gesture.rawValue) · \(points.count)/21"
                let font = UIFont.boldSystemFont(ofSize: max(16, size.width / 35))
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
                let textSize = (title as NSString).size(withAttributes: attributes)
                let box = CGRect(x: max(0, min(wrist.x, size.width - textSize.width - 16)),
                    y: max(0, min(wrist.y + 12, size.height - textSize.height - 12)),
                    width: textSize.width + 16, height: textSize.height + 10)
                context.setFillColor(UIColor.black.withAlphaComponent(0.75).cgColor)
                context.fill(box)
                (title as NSString).draw(at: CGPoint(x: box.minX + 8, y: box.minY + 5), withAttributes: attributes)
            }
        }
    }
}
