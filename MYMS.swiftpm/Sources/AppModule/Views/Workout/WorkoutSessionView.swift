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
            Picker("측정 방식", selection: Binding(
                get: { coach.measurementMode },
                set: { coach.setMeasurementMode($0) }
            )) {
                ForEach(Coach.MeasurementMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .disabled(!coach.canSelect || coach.isSimulating)
            if coach.measurementMode == .acceleration {
                Text("보드를 손에 들고 움직여 코치 흐름을 시험합니다. 고정된 보드로 사람의 운동을 측정할 수 없으며, 이 기록에는 포인트가 적립되지 않습니다.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if coach.canSelect || coach.isSimulating {
                Toggle("센서 없이 시연", isOn: Binding(
                    get: { coach.isSimulating },
                    set: { coach.setSimulation($0) }
                ))
                .disabled(!coach.canSelect)
            }

            SensorConnectionCard(coach: coach)

            VStack(alignment: .leading, spacing: 8) {
                Text("현재 측정값").font(.headline)
                if !coach.isSimulating, coach.measurementMode == .acceleration {
                    Text(coach.acceleration.map { "\($0.formatted(.number.precision(.fractionLength(2)))) g" } ?? "IMU 데이터 대기 중")
                        .font(.title2.monospacedDigit())
                } else if let millimeters = coach.latestDistance {
                    Text("\((millimeters / 10).formatted(.number.precision(.fractionLength(1)))) cm")
                        .font(.title2.monospacedDigit())
                } else {
                    Text(coach.connected ? "유효 거리값 대기 중" : "센서 데이터 대기 중")
                        .foregroundStyle(.secondary)
                }
                if coach.isSimulating {
                    Text("시연 기록과 포인트는 저장되지 않습니다.")
                        .foregroundStyle(.secondary)
                } else if coach.canSelect && coach.measurementMode == .distance {
                    Text(coach.workout.exercise.placement).foregroundStyle(.secondary)
                } else if coach.phase == .training && coach.measurementMode == .distance && coach.latestDistance == nil {
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

            VStack(alignment: .leading, spacing: 8) {
                Text("운동 환경").font(.headline)
                LabeledContent("운동기구", value: coach.equipment.rawValue)
                LabeledContent("장소", value: coach.place.rawValue)
                LabeledContent("신발", value: coach.footwear.rawValue)
                Text("센서 탭에서 밝기·바닥 경사를 측정하고 환경을 선택하세요. 보드를 바닥에 둔 상태로 운동 시작을 누르면 환경이 저장됩니다. IMU 동작 테스트는 그다음 보드를 들어 진행하세요.")
                    .font(.footnote).foregroundStyle(.secondary)
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
                if coach.restInterrupted {
                    Text("휴식을 멈췄습니다. 센서를 연결한 뒤 남은 휴식 재개 또는 다음 세트를 눌러주세요.")
                        .font(.footnote)
                }
            }
            if coach.phase == .paused {
                Text("센서를 연결한 뒤 재개를 눌러주세요. 앱이 꺼져 있거나 센서 연결이 끊긴 동안의 동작은 집계되지 않습니다.")
                    .font(.footnote)
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
                Button("운동 시작") { coach.gesture(4) }.disabled(!coach.canMeasure || !store.loaded || !coach.canSelect)
            case .calibrating, .training:
                Button("일시정지") { coach.pause() }
            case .paused:
                Button("재개") { coach.gesture(4) }.disabled(!coach.canMeasure || !store.loaded)
                Button("운동 종료") { coach.finish() }
            case .resting:
                if coach.restInterrupted {
                    Button("남은 휴식 재개") { coach.resumeRest() }
                        .disabled(!coach.canMeasure || !store.loaded)
                }
                Button("다음 세트") { coach.gesture(1) }.disabled(!coach.canMeasure || !store.loaded)
                Button("운동 종료") { coach.finish() }
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(coach.persistenceError != nil)
    }
}
