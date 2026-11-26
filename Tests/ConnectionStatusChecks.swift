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
        let first = "0123456789ABCDEF"
        let other = "FEDCBA9876543210"
        assert(Coach.matchesHardwareID(first, advertised: nil, remembered: first))
        assert(Coach.matchesHardwareID(first, advertised: first, remembered: first))
        assert(!Coach.matchesHardwareID(other, advertised: nil, remembered: first))
        assert(!Coach.matchesHardwareID(first, advertised: other, remembered: first))
        assert(Coach.matchesHardwareID(first, advertised: nil, remembered: nil))
        var gap = Coach.DistanceGap()
        for (distance, expected) in [(300.0, true), (0, false), (180, true),
                                     (0, false), (0, false), (300, true),
                                     (0, false), (0, false), (0, true), (0, true),
                                     (300, true), (0, false)] {
            assert(gap.shouldProcess(distance) == expected)
        }
        print("ConnectionStatusChecks passed")
    }
}
