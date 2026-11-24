import Foundation

@main
struct HandLandmarkChecks {
    static func main() {
        let points = (0..<21).map { HandLandmark(index: $0, x: 0.5, y: 0.5) }
        precondition(TrackedHand(points: points, category: "Open_Palm", score: 0.9).gesture == .openPalm)
        precondition(TrackedHand(points: points, category: "Closed_Fist", score: 0.9).gesture == .closedFist)
        for score: Float in [0, 0.59, .nan, .infinity, 1.1] {
            precondition(TrackedHand(points: points, category: "Closed_Fist", score: score).gesture == .unknown)
        }
        precondition(TrackedHand(points: points, category: "Victory", score: 0.99).gesture == .unknown)
        precondition(TrackedHand(points: [], category: "Closed_Fist", score: 0.99).gesture == .unknown)
        let invalid = [HandLandmark(index: 0, x: .nan, y: 0.5), HandLandmark(index: 1, x: 0.5, y: .infinity), HandLandmark(index: 2, x: -0.1, y: 0.5)]
        precondition(TrackedHand(points: invalid, category: "Open_Palm", score: 0.99).visiblePoints.isEmpty)
        precondition(TrackedHand(points: Array(points.dropLast()), category: "Closed_Fist", score: 0.99).gesture == .unknown)
        precondition(HandLandmark.connections.count == 21)
        precondition(HandLandmark.connections.allSatisfy { (0..<21).contains($0.0) && (0..<21).contains($0.1) })
        print("Hand checks passed: 21 points, open/fist thresholds, partial/invalid/empty results")
    }
}
