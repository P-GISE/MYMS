import SwiftUI

struct ExerciseGuide: View {
    @Environment(\.dismiss) private var dismiss
    let plan: Workout
    let canSelect: Bool
    var onSelect: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: plan.exercise.symbol).font(.title)
                        Text(plan.exercise.rawValue).font(.largeTitle.bold())
                        Text("\(plan.level.title) · \(plan.target)회 × \(plan.sets)세트 · 휴식 \(plan.rest)초")
                            .font(.subheadline)
                    }
                    .padding(.vertical, 8)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .listRowBackground(Color(red: 0.05, green: 0.29, blue: 0.22))
                }
                Section("운동 방법") {
                    ExerciseAnimation(exercise: plan.exercise)
                    ForEach(plan.exercise.steps.indices, id: \.self) { index in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("\(index + 1)").font(.headline.monospacedDigit()).foregroundStyle(.tint)
                            Text(plan.exercise.steps[index])
                        }
                    }
                }
                Section("센서 배치와 시작 자세") {
                    Text(plan.exercise.placement)
                    Text("운동을 시작하면 앱이 2초 동안 시작 높이를 측정합니다. 화면에 ‘운동 중’이 표시될 때까지 첫 자세를 유지하세요.")
                    if let note = plan.exercise.measurementNote {
                        Label(note, systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    ForEach(Level.allCases, id: \.self) { level in
                        LabeledContent(level.title, value: plan.exercise.depth(for: level).formatted(.percent))
                            .fontWeight(level == plan.level ? .semibold : .regular)
                    }
                } header: {
                    Text("난이도별 거리 변화 기준")
                } footer: {
                    Text("시작 거리보다 센서에 해당 비율만큼 가까워졌다가, 시작 거리와의 차이가 \(plan.exercise.returnDepth.formatted(.percent)) 이하로 돌아오면 1회로 셉니다. 앱은 센서 거리로 횟수를 판정합니다.")
                }
            }
            .navigationTitle("운동 안내")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("이 운동 준비하기", action: onSelect)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!canSelect)
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(.regularMaterial)
            }
        }
    }
}
