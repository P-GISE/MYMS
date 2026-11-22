import SwiftUI

struct PlanEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var plan: Workout
    let ageGroup: AgeGroup?
    @State private var experience = Level.easy
    var onSave: (Workout) -> Void

    private var recommendedReps: Int {
        let base: Int
        switch plan.exercise {
        case .pushup: base = 5
        case .squat: base = 8
        case .bridge: base = 7
        case .kneeRaise: base = 6
        }
        return base + (experience.rawValue - 1) * 2 - (ageGroup?.volumeAdjustment ?? 0)
    }

    private var recommendedSets: Int {
        let reduction = ageGroup?.volumeAdjustment == 2 ? 1 : 0
        return max(1, experience.rawValue - reduction)
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("운동 종류", selection: $plan.exercise) {
                    ForEach(Exercise.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Section {
                    Picker("운동 경험", selection: $experience) {
                        ForEach(Level.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    LabeledContent("추천", value: "\(experience.title) · \(recommendedReps)회 × \(recommendedSets)세트")
                    Button("추천값 적용") {
                        plan.level = experience
                        plan.target = recommendedReps
                        plan.sets = recommendedSets
                    }
                } header: {
                    Text(ageGroup.map { "\($0.rawValue) 운동 추천" } ?? "운동 추천")
                } footer: {
                    Text(ageGroup == nil
                         ? "설정에서 연령대를 선택하면 추천값에 반영됩니다."
                         : "선택한 운동과 경험에 따른 시작값입니다. 적용 후 직접 바꿀 수 있습니다.")
                }
                Picker("난이도", selection: $plan.level) {
                    ForEach(Level.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                LabeledContent("깊이 기준", value: plan.exercise.depth(for: plan.level).formatted(.percent))
                Stepper("목표 \(plan.target)회", value: $plan.target, in: 1...100)
                Stepper("\(plan.sets)세트", value: $plan.sets, in: 1...10)
                Stepper("휴식 \(plan.rest)초", value: $plan.rest, in: 5...300, step: 5)
            }
            .navigationTitle("운동 설정")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { onSave(plan); dismiss() }
                }
            }
        }
    }
}
