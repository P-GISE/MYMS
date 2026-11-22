import Foundation

enum Exercise: String, Codable, CaseIterable {
    case pushup = "푸시업", squat = "스쿼트"
    case bridge = "힙 브리지", kneeRaise = "앉아서 무릎 들기"

    var cloudCode: String {
        switch self {
        case .pushup: "pushup"
        case .squat: "squat"
        case .bridge: "bridge"
        case .kneeRaise: "knee-raise"
        }
    }

    var symbol: String {
        switch self {
        case .pushup: "figure.strengthtraining.traditional"
        case .squat: "figure.strengthtraining.functional"
        case .bridge: "figure.cooldown"
        case .kneeRaise: "figure.core.training"
        }
    }

    var returnDepth: Double { self == .pushup ? 0.15 : 0.10 }

    func depth(for level: Level) -> Double {
        let thresholds: [Double]
        switch self {
        case .pushup: thresholds = [0.35, 0.50, 0.65]
        case .squat: thresholds = [0.20, 0.30, 0.45]
        case .bridge, .kneeRaise: thresholds = [0.15, 0.25, 0.35]
        }
        return thresholds[level.rawValue - 1]
    }

    var placement: String {
        switch self {
        case .pushup: "센서를 가슴 바로 아래 바닥에 놓고 위를 향하게 하세요."
        case .squat: "센서를 엉덩이 바로 아래 바닥에 놓고 위를 향하게 하세요. 발이나 다리가 센서 앞을 가리지 않게 위치를 맞추세요."
        case .bridge: "센서를 고정 거치대에 달아 골반 바로 위에서 아래를 향하게 하세요. 골반을 들어 올렸을 때 센서와 닿지 않을 만큼 공간을 확보하세요."
        case .kneeRaise: "센서를 고정 거치대에 달아 들어 올릴 다리의 무릎 가까운 허벅지 위에서 아래를 향하게 하세요. 세트마다 한쪽 다리만 측정하고, 반대쪽은 센서 위치를 옮긴 뒤 새 세트에서 진행하세요."
        }
    }

    var measurementNote: String? {
        switch self {
        case .pushup: nil
        case .squat: "스쿼트는 센서와 몸 사이가 멀어 거리 측정이 끊길 수 있어 실측이 필요합니다."
        case .bridge, .kneeRaise: "난이도별 기준은 초기값입니다. 거치 높이에 따라 같은 동작의 거리 변화 비율이 달라지므로 설치 후 실측이 필요합니다."
        }
    }

    var steps: [String] {
        switch self {
        case .pushup: [
            "손을 어깨너비 정도로 짚고 팔을 펴세요. 무릎을 바닥에 대고 시작해도 됩니다.",
            "팔꿈치를 굽혀 가슴을 센서 쪽으로 내리세요.",
            "바닥을 밀어 가슴을 처음 높이로 되돌리세요."
        ]
        case .squat: [
            "발을 어깨너비 정도로 벌리고 엉덩이가 센서 위에 오도록 서세요.",
            "엉덩이를 뒤로 보내며 무릎을 굽히세요. 무릎은 발끝 방향을 향하게 하세요.",
            "발바닥으로 바닥을 밀며 처음 선 자세로 돌아오세요."
        ]
        case .bridge: [
            "등을 대고 누워 무릎을 굽히고 발바닥을 바닥에 붙이세요.",
            "발바닥으로 바닥을 누르며 골반을 센서 쪽으로 들어 올리세요.",
            "골반을 천천히 내려 처음 자세로 돌아오세요."
        ]
        case .kneeRaise: [
            "흔들리지 않는 의자에 앉아 두 발을 바닥에 두세요.",
            "몸통을 고정하고 한쪽 무릎을 굽힌 채 허벅지를 센서 쪽으로 들어 올리세요.",
            "발을 천천히 바닥으로 내려 처음 자세로 돌아오세요."
        ]
        }
    }
}

enum Level: Int, Codable, CaseIterable {
    case easy = 1, normal, deep
    var title: String { ["초급", "중급", "상급"][rawValue - 1] }
}

struct Workout: Codable, Identifiable, Equatable {
    var id = UUID()
    var exercise = Exercise.pushup
    var level = Level.normal
    var target = 10
    var sets = 3
    var rest = 30

    var cloudFields: [String: Any] {
        ["exercise_slug": exercise.cloudCode, "level": level.rawValue, "target_reps": target,
         "target_sets": sets, "rest_seconds": rest]
    }
}

struct WorkoutRecord: Codable, Identifiable {
    var id = UUID()
    var workout: Workout
    var date = Date()
    var reps: Int
    var sets: Int
    var seconds: Int
    var note = ""
    var points: Int
    var environment: SensorEnvironment? = nil
    var measurementSource: String? = nil
}
