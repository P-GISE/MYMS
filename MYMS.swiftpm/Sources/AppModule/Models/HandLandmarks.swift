import Foundation

enum HandGesture: String {
    case openPalm = "손바닥 펼침"
    case closedFist = "주먹"
    case unknown = "손모양 판별 중"
}

struct HandLandmark {
    let index: Int
    let x: Double
    let y: Double

    var isVisible: Bool {
        (0..<21).contains(index) && x.isFinite && y.isFinite && (0...1).contains(x) && (0...1).contains(y)
    }

    static let connections: [(Int, Int)] = [
        (0,1), (1,2), (2,3), (3,4),
        (0,5), (5,6), (6,7), (7,8),
        (5,9), (9,10), (10,11), (11,12),
        (9,13), (13,14), (14,15), (15,16),
        (13,17), (0,17), (17,18), (18,19), (19,20)
    ]
}

struct TrackedHand {
    let points: [HandLandmark]
    let category: String?
    let score: Float

    var visiblePoints: [HandLandmark] { points.filter(\.isVisible) }

    var gesture: HandGesture {
        guard points.count == 21, Set(points.map(\.index)).count == 21,
              points.allSatisfy(\.isVisible), score.isFinite, (0.6...1).contains(score) else { return .unknown }
        switch category {
        case "Open_Palm": return .openPalm
        case "Closed_Fist": return .closedFist
        default: return .unknown
        }
    }
}
