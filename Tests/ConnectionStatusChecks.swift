import Foundation

@main
struct ConnectionStatusChecks {
    static func main() {
        let state = Coach.ConnectionStage.measurement
        assert(state(nil, 10) == .verifying)
        assert(state(9.5, 10) == .receiving)
        assert(state(8, 10) == .receiving)
        assert(state(7.9, 10) == .stale)
        assert(state(11, 10) == .stale)
        assert(state(.nan, 10) == .stale)
        assert(Coach.parseHardwareID("0123456789abcdef") == "0123456789ABCDEF")
        assert(Coach.parseHardwareID("0123456789ABCDE") == nil)
        assert(Coach.parseHardwareID("0123456789ABCDEG") == nil)
        assert(Coach.parseHardwareID("０123456789ABCDEF") == nil)
        print("ConnectionStatusChecks passed")
    }
}
