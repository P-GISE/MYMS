import SwiftUI

struct ExerciseAnimation: View {
    let exercise: Exercise
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt: Date?
    @State private var elapsed = 0.0

    private let cycle = 3.2

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: startedAt == nil)) { timeline in
                let motion = elapsed + (startedAt.map { max(0, timeline.date.timeIntervalSince($0)) } ?? 0)
                let phase = (1 - cos(motion / cycle * 2 * .pi)) / 2
                illustration(phase: phase)
                    .overlay(alignment: .bottomLeading) {
                        Text(phase < 0.5 ? "시작 자세" : (exercise == .pushup || exercise == .squat ? "내린 자세" : "들어 올린 자세"))
                            .font(.caption.weight(.semibold))
                            .padding(8)
                    }
                    .accessibilityHidden(true)
            }
            HStack {
                Button {
                    if let startedAt {
                        elapsed = (elapsed + Date().timeIntervalSince(startedAt)).truncatingRemainder(dividingBy: cycle)
                        self.startedAt = nil
                    } else {
                        startedAt = Date()
                    }
                } label: {
                    Label(startedAt == nil ? "재생" : "일시정지",
                          systemImage: startedAt == nil ? "play.fill" : "pause.fill")
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("자세 전환") {
                    startedAt = nil
                    elapsed = elapsed < cycle / 4 ? cycle / 2 : 0
                }
                .buttonStyle(.bordered)
            }
        }
        .onAppear {
            if !reduceMotion { startedAt = Date() }
        }
        .onDisappear { startedAt = nil }
    }

    private func illustration(phase: Double) -> some View {
        let poses = exercise.demonstration
        return Canvas { context, size in
            let scale = min(size.width / 100, size.height / 76)
            func point(_ x: Double, _ y: Double) -> CGPoint {
                CGPoint(x: (size.width - 100 * scale) / 2 + x * scale,
                        y: (size.height - 76 * scale) / 2 + y * scale)
            }
            func joint(_ index: Int) -> CGPoint {
                let a = poses.start[index]
                let b = poses.end[index]
                return point(a.x + (b.x - a.x) * phase, a.y + (b.y - a.y) * phase)
            }
            func line(_ points: [CGPoint], color: Color, width: Double) {
                var path = Path()
                path.addLines(points)
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            }
            let ink = Color(red: 0.06, green: 0.32, blue: 0.25)
            line([point(9, 64), point(91, 64)], color: ink.opacity(0.22), width: 2)
            if exercise == .kneeRaise {
                line([point(36, 44), point(57, 44), point(57, 63)], color: ink.opacity(0.35), width: 3)
                line([point(36, 44), point(36, 63)], color: ink.opacity(0.35), width: 3)
                line([joint(2), point(63, 47), point(64, 62)], color: ink.opacity(0.35), width: 4)
            }
            line([joint(0), joint(1), joint(2), joint(3), joint(4)], color: ink, width: 5)
            line([joint(1), joint(5), joint(6)], color: ink, width: 4)
            let head = joint(0)
            let radius = 5.2 * scale
            context.fill(Path(ellipseIn: CGRect(x: head.x - radius, y: head.y - radius,
                                                width: radius * 2, height: radius * 2)), with: .color(ink))
        }
        .frame(height: 200)
        .background(Color(red: 0.90, green: 0.96, blue: 0.93), in: RoundedRectangle(cornerRadius: 16))
        .foregroundStyle(Color(red: 0.06, green: 0.32, blue: 0.25))
    }
}

private extension Exercise {
    // Joint order is head, shoulder, hip, knee, foot, elbow, hand.
    var demonstration: (start: [CGPoint], end: [CGPoint]) {
        let positions: ([(Double, Double)], [(Double, Double)])
        switch self {
        case .pushup:
            positions = ([(75, 24), (64, 32), (42, 45), (28, 54), (14, 63), (67, 48), (68, 63)],
                         [(78, 46), (66, 50), (43, 54), (28, 58), (14, 63), (56, 57), (68, 63)])
        case .squat:
            positions = ([(49, 10), (49, 20), (48, 37), (49, 50), (49, 63), (55, 29), (61, 34)],
                         [(57, 23), (51, 32), (39, 47), (55, 50), (49, 63), (61, 31), (72, 28)])
        case .bridge:
            positions = ([(20, 59), (29, 60), (50, 61), (64, 43), (75, 63), (39, 63), (52, 63)],
                         [(20, 59), (29, 60), (49, 46), (64, 38), (75, 63), (39, 63), (52, 63)])
        case .kneeRaise:
            positions = ([(43, 12), (44, 23), (45, 43), (64, 45), (67, 63), (49, 35), (57, 41)],
                         [(43, 12), (44, 23), (45, 43), (64, 32), (73, 49), (47, 34), (57, 41)])
        }
        return (positions.0.map { CGPoint(x: $0.0, y: $0.1) },
                positions.1.map { CGPoint(x: $0.0, y: $0.1) })
    }
}
