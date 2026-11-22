import Foundation

@main
struct SensorDataChecks {
    static func main() {
        // Given little-endian BLE data, when decoded, then values and invalid packets are distinguished.
        assert(SensorPayload.float32(Data([0, 0, 128, 63]), in: 0...32) == 1)
        assert(SensorPayload.float32(Data([0, 0, 192, 127]), in: 0...32) == nil)
        assert(SensorPayload.float32(Data([0, 0, 128, 127]), in: 0...32) == nil)
        assert(SensorPayload.float32(Data([0, 0, 128]), in: 0...32) == nil)
        assert(SensorPayload.float32(Data([0, 0, 128, 191]), in: 0...32) == nil)

        // Given a sustained movement peak, when samples repeat, then it counts only once until rearmed.
        var counter = AccelerationCounter()
        assert(!counter.observe(1.8, at: -0.1))
        assert(!counter.observe(1, at: 0))
        assert(counter.observe(1.6, at: 0.1))
        assert(!counter.observe(1.7, at: 1))
        assert(!counter.observe(1, at: 1.1))
        assert(counter.observe(1.6, at: 1.2))
        assert(!counter.observe(1, at: 1.3))
        assert(!counter.observe(1.6, at: 1.4))
        assert(counter.observe(1.6, at: 1.8))
        assert(!counter.observe(.nan, at: 2))

        func packet(_ values: [Float]) -> Data {
            Data(values.flatMap { value in
                (0..<4).map { UInt8(truncatingIfNeeded: value.bitPattern >> ($0 * 8)) }
            })
        }
        let level = GravityVector(x: 0, y: 0, z: 1)
        let tilted = SensorPayload.gravity(packet([0.5, 0, 0.8660254]))!
        assert(abs(level.angle(to: tilted) - 30) < 0.01)
        assert(level.angle(to: GravityVector(x: 0, y: 0, z: -1)) == 0)
        assert(SensorPayload.gravity(packet([0, .nan, 1])) == nil)
        assert(SensorPayload.gravity(packet([0, 1])) == nil)
        var window = StableGravityWindow()
        for index in 0..<20 { assert(window.observe(level, at: Double(index) / 10) == nil) }
        assert(window.observe(level, at: 2) != nil)
        assert(window.observe(tilted, at: 2.1) == nil)
        assert(window.progress == 0)
        assert(window.observe(GravityVector(x: 0, y: 0, z: 2), at: 2.2) == nil)
        assert(window.observe(level, at: 4) == nil)

        let snapshot = SensorEnvironment(brightnessRaw: 20, brightnessReference: 100, inclineDegrees: 4,
                                         measuredAt: Date(timeIntervalSince1970: 0),
                                         equipment: WorkoutEquipment.none, place: .home, footwear: .barefoot)
        let restored = try! JSONDecoder().decode(SensorEnvironment.self, from: JSONEncoder().encode(snapshot))
        assert(restored.brightnessRaw == 20 && restored.inclineDegrees == 4)
        assert(restored.equipment == WorkoutEquipment.none && restored.place == .home && restored.footwear == .barefoot)
        assert(restored.brightnessDescription == "기준보다 어두움")
        assert(restored.inclineDescription == "경사 있음 (초기 기준)")
        let legacy = Data(#"{"temperatureCelsius":24,"humidityPercent":45,"pressureKPa":101.3,"measuredAt":0}"#.utf8)
        let old = try! JSONDecoder().decode(SensorEnvironment.self, from: legacy)
        assert(old.temperatureCelsius == 24 && old.brightnessRaw == nil && old.equipment == nil)
        assert(old.brightnessDescription == "미수신" && old.inclineDescription == "미측정")
        print("PASS: BLE decoding, invalid payloads, IMU counter, stable floor window, tilt angle, context roundtrip, legacy decoding")
    }
}
