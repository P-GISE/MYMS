import Foundation

struct SensorEnvironment: Codable {
    // Preserve old local records without collecting these fields in new sessions.
    var temperatureCelsius: Double?
    var humidityPercent: Double?
    var pressureKPa: Double?
    var brightnessRaw: Double?
    var brightnessReference: Double?
    var inclineDegrees: Double?
    var measuredAt: Date
    var equipment: WorkoutEquipment?
    var place: WorkoutPlace?
    var footwear: WorkoutFootwear?

    var brightnessDescription: String {
        guard let brightnessRaw else { return "미수신" }
        guard let brightnessReference, brightnessReference > 0 else { return "기준 미설정" }
        // shortcut: relative 25% cutoff; tune after measurements in real exercise spaces.
        return brightnessRaw <= brightnessReference * 0.25 ? "기준보다 어두움" : "기준 수준"
    }

    var inclineDescription: String {
        guard let inclineDegrees else { return "미측정" }
        return inclineDegrees <= 3 ? "평평한 편 (초기 기준)" : "경사 있음 (초기 기준)"
    }
}

enum WorkoutEquipment: String, Codable, CaseIterable {
    case unspecified = "미선택", none = "없음", available = "있음"
}

enum WorkoutPlace: String, Codable, CaseIterable {
    case unspecified = "미선택", home = "집", gym = "체육관·헬스장", outdoors = "야외", other = "기타"
}

enum WorkoutFootwear: String, Codable, CaseIterable {
    case unspecified = "미선택", barefoot = "맨발", socks = "양말", runningShoes = "러닝화", other = "기타 신발"
}

struct GravityVector {
    let x: Double
    let y: Double
    let z: Double

    var magnitude: Double { sqrt(x * x + y * y + z * z) }

    func angle(to other: GravityVector, plane: Bool = true) -> Double {
        let dot = (x * other.x + y * other.y + z * other.z) / (magnitude * other.magnitude)
        return acos(min(1, max(-1, plane ? abs(dot) : dot))) * 180 / .pi
    }
}

struct StableGravityWindow {
    private var samples: [(time: TimeInterval, vector: GravityVector)] = []
    private(set) var progress = 0.0

    mutating func observe(_ vector: GravityVector, at seconds: TimeInterval) -> GravityVector? {
        // shortcut: 1g ±8%, 2° stability and 2 seconds; calibrate on the final mounting surface.
        guard vector.magnitude.isFinite, (0.92...1.08).contains(vector.magnitude) else {
            self = StableGravityWindow()
            return nil
        }
        if let first = samples.first,
           vector.angle(to: first.vector, plane: false) > 2 || seconds - (samples.last?.time ?? seconds) > 0.5 {
            samples.removeAll()
        }
        samples.append((seconds, vector))
        if samples.count > 30 { samples.removeFirst(samples.count - 30) }
        progress = min(1, (seconds - samples[0].time) / 2)
        guard samples.count >= 15, progress >= 1 else { return nil }
        let count = Double(samples.count)
        return GravityVector(x: samples.reduce(0) { $0 + $1.vector.x } / count,
                             y: samples.reduce(0) { $0 + $1.vector.y } / count,
                             z: samples.reduce(0) { $0 + $1.vector.z } / count)
    }
}

struct AccelerationSample: Identifiable {
    let id = UUID()
    let date: Date
    let magnitude: Double
}

enum SensorPayload {
    static func distanceMillimeters(_ data: Data) -> Double? {
        guard data.count == 2 else { return nil }
        let bytes = Array(data)
        let millimeters = Int(bytes[0]) | (Int(bytes[1]) << 8)
        // Match the firmware's valid VL53L0X range; zero remains the no-measurement sentinel.
        return millimeters <= 2000 ? Double(millimeters) : nil
    }
    static func gravity(_ data: Data) -> GravityVector? {
        guard data.count == 12,
              let x = float32(Data(data.prefix(4)), in: -16...16),
              let y = float32(Data(data.dropFirst(4).prefix(4)), in: -16...16),
              let z = float32(Data(data.suffix(4)), in: -16...16) else { return nil }
        return GravityVector(x: x, y: y, z: z)
    }
    static func float32(_ data: Data, in range: ClosedRange<Double>) -> Double? {
        guard data.count == 4 else { return nil }
        let bits = data.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << ($1.offset * 8) }
        let value = Double(Float(bitPattern: bits))
        return value.isFinite && range.contains(value) ? value : nil
    }
}

struct AccelerationCounter {
    private var armed = false
    private var lastRep = -Double.infinity

    mutating func observe(_ magnitude: Double, at seconds: TimeInterval) -> Bool {
        guard magnitude.isFinite, (0...32).contains(magnitude) else { return false }
        if magnitude <= 1.1 { armed = true }
        guard armed, magnitude >= 1.5, seconds - lastRep >= 0.5 else { return false }
        armed = false
        lastRep = seconds
        return true
    }
}
