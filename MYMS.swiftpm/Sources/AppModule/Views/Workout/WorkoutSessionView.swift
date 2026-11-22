import SwiftUI

extension WorkoutHome {
    var session: some View {
        NavigationStack {
            GeometryReader { geometry in
                let wide = geometry.size.width >= 780 && !typeSize.isAccessibilitySize
                let inset: CGFloat = wide ? 28 : 16
                let width = min(wide ? 960 : 540, max(0, geometry.size.width - inset * 2))
                let panelWidth = wide ? (width - 20) / 2 : width
                let layout = wide
                    ? AnyLayout(HStackLayout(alignment: .top, spacing: 20))
                    : AnyLayout(VStackLayout(spacing: 16))

                ScrollView {
                    layout {
                        sensorPanel.frame(width: panelWidth)
                        VStack(spacing: 16) {
                            progressPanel
                            sessionControls
                            sessionResult
                        }
                        .frame(width: panelWidth)
                    }
                    .padding(inset)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("운동")
        }
    }

    private var sensorPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if coach.canSelect || coach.isSimulating {
                Toggle("센서 없이 시연", isOn: Binding(
                    get: { coach.isSimulating },
                    set: { coach.setSimulation($0) }
                ))
                .disabled(!coach.canSelect)
            }

            VStack(alignment: .leading, spacing: 8) {
                Label(coach.isSimulating ? "시연 모드 · 가상 센서" : coach.connection,
                      systemImage: coach.isSimulating ? "waveform" : "antenna.radiowaves.left.and.right")
                    .font(.headline)
                if let millimeters = coach.latestDistance {
                    Text("\((millimeters / 10).formatted(.number.precision(.fractionLength(1)))) cm")
                        .font(.title2.monospacedDigit())
                } else {
                    Text(coach.connected ? "유효 거리값 대기 중" : "센서 데이터 대기 중")
                        .foregroundStyle(.secondary)
                }
                if coach.isSimulating {
                    Text("시연 기록과 포인트는 저장되지 않습니다.")
                        .foregroundStyle(.secondary)
                } else if coach.canSelect {
                    Text(coach.workout.exercise.placement).foregroundStyle(.secondary)
                } else if coach.phase == .training && coach.latestDistance == nil {
                    Text("측정 일시 중지").foregroundStyle(.orange)
                }
                if coach.phase == .calibrating {
                    ProgressView(value: coach.calibrationProgress)
                        .accessibilityLabel("시작 거리 측정 진행률")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private var progressPanel: some View {
        VStack(spacing: 8) {
            Text(coach.workout.exercise.rawValue).font(.title2.bold())
            Text("\(coach.workout.level.title) · 세트 \(coach.set) / \(coach.workout.sets)")
            Text("\(coach.reps) / \(coach.workout.target)")
                .font(.system(size: repFontSize, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5).lineLimit(1).monospacedDigit()
                .accessibilityLabel("\(coach.workout.target)회 중 \(coach.reps)회")
            ProgressView(value: Double(coach.reps), total: Double(coach.workout.target)).tint(.mint)
            Text(coach.phase.rawValue).font(.headline)
            if coach.phase == .resting {
                Text("남은 휴식 \(coach.restSeconds)초").monospacedDigit()
            }
            if coach.shallow {
                Text("동작 범위를 조금 더 늘려 보세요").foregroundStyle(.yellow)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .foregroundStyle(.white)
        .background(Color(red: 0.05, green: 0.29, blue: 0.22), in: RoundedRectangle(cornerRadius: 24))
    }

    @ViewBuilder
    private var sessionResult: some View {
        if coach.phase == .finished, let summary = coach.summary {
            VStack(alignment: .leading, spacing: 8) {
                Text(coach.isSimulating ? "시연 결과" : "운동 결과").font(.headline)
                LabeledContent("유효 횟수", value: "\(summary.reps)회")
                LabeledContent("완료 세트", value: "\(summary.sets) / \(summary.workout.sets)")
                LabeledContent("경과 시간", value: "\(summary.seconds)초")
                if let saved = store.records.first(where: { $0.id == summary.id }) {
                    LabeledContent("획득 포인트", value: "\(saved.points) P")
                }
            }
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private var sessionControls: some View {
        VStack(spacing: 12) {
            if coach.isSimulating && coach.phase == .training {
                Button("가상 동작 1회") { coach.simulateRep() }
                    .disabled(coach.isSimulatingRep)
            }
            switch coach.phase {
            case .ready, .finished:
                Button("운동 시작") { coach.gesture(4) }.disabled(!coach.canMeasure || !store.loaded)
            case .calibrating, .training:
                Button("일시정지") { coach.pause() }
            case .paused:
                Button("재개") { coach.gesture(4) }.disabled(!coach.canMeasure || !store.loaded)
                Button("운동 종료") { coach.finish() }
            case .resting:
                Button("다음 세트") { coach.gesture(1) }.disabled(!coach.canMeasure || !store.loaded)
                Button("운동 종료") { coach.finish() }
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }
}
