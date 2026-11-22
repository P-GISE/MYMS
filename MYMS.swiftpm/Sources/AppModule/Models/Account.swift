import Foundation

enum AgeGroup: String, Codable, CaseIterable {
    case teens = "10대", twenties = "20대", thirties = "30대", forties = "40대"
    case fifties = "50대", sixties = "60대", older = "70대 이상"

    var cloudCode: String {
        switch self {
        case .teens: "teens"
        case .twenties: "twenties"
        case .thirties: "thirties"
        case .forties: "forties"
        case .fifties: "fifties"
        case .sixties: "sixties"
        case .older: "older"
        }
    }

    var volumeAdjustment: Int {
        switch self {
        case .twenties, .thirties, .forties: 0
        case .teens, .fifties: 1
        case .sixties, .older: 2
        }
    }
}

struct LocalAccount: Codable {
    let id: UUID
    let email: String
    var ageGroup: AgeGroup?
}
