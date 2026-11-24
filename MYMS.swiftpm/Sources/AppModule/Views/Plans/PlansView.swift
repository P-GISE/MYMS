import SwiftUI

extension WorkoutHome {
    var plans: some View {
        NavigationStack {
            List {
                if store.loaded {
                    if store.plans.isEmpty {
                        Section {
                            VStack(alignment: .leading, spacing: 14) {
                                Image(systemName: "list.bullet.clipboard")
                                    .font(.largeTitle).foregroundStyle(MYMSStyle.lime)
                                    .accessibilityHidden(true)
                                Text("첫 운동 계획을 만들어 보세요")
                                    .font(.title2.bold())
                                Text("운동을 고르고 한 세트의 목표 횟수를 정하세요.")
                                    .font(.body)
                                Button { editing = Workout() } label: {
                                    Label("운동 계획 추가", systemImage: "plus")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(MYMSStyle.lime).foregroundStyle(MYMSStyle.ink)
                                .controlSize(.large)
                            }
                            .padding(.vertical, 12)
                            .foregroundStyle(.white)
                            .listRowBackground(MYMSStyle.ink)
                        }
                        if store.points > 0 { planSummary }
                    } else {
                        planSummary
                        Section("내 계획") {
                            ForEach(store.plans) { plan in
                                planRow(plan)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(MYMSStyle.canvas)
            .navigationTitle("운동 계획")
            .toolbar {
                if !store.plans.isEmpty {
                    Button("운동 계획 추가", systemImage: "plus") { editing = Workout() }
                        .disabled(!store.loaded)
                }
            }
            .sheet(item: $guide) { plan in
                ExerciseGuide(plan: plan, canSelect: coach.canSelect) {
                    prepare(plan)
                }
            }
            .sheet(item: $editing) { plan in
                PlanEditor(plan: plan, ageGroup: account.ageGroup) { updated in
                    if let index = store.plans.firstIndex(where: { $0.id == updated.id }) {
                        store.plans[index] = updated
                    } else {
                        store.plans.append(updated)
                    }
                }
            }
            .confirmationDialog("운동 계획을 삭제할까요?", isPresented: Binding(
                get: { deleting != nil }, set: { if !$0 { deleting = nil } }
            ), titleVisibility: .visible) {
                Button("삭제", role: .destructive) {
                    if let deleting { store.plans.removeAll { $0.id == deleting.id } }
                    deleting = nil
                }
            }
        }
    }
    private var planSummary: some View {
        Section {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 32) { planMetrics }
                VStack(alignment: .leading, spacing: 16) { planMetrics }
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(.white)
            .listRowBackground(MYMSStyle.ink)
        }
    }

    @ViewBuilder private var planMetrics: some View {
        planMetric("저장한 계획", value: "\(store.plans.count)개", symbol: "list.bullet.clipboard")
        planMetric("누적 포인트", value: "\(store.points) P", symbol: "bolt.fill")
    }

    private func planMetric(_ title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold)).foregroundStyle(MYMSStyle.lime)
            Text(value).font(.largeTitle.bold()).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func planRow(_ plan: Workout) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                planIdentity(plan).fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 8)
                planActions(plan)
                planMenu(plan)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 8) {
                    planIdentity(plan)
                    Spacer(minLength: 0)
                    planMenu(plan)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { planActions(plan) }
                    VStack(alignment: .leading, spacing: 8) { planActions(plan) }
                }
            }
        }
        .padding(.vertical, 8)
        .listRowBackground(MYMSStyle.surface)
        .swipeActions(edge: .leading) {
            Button("편집", systemImage: "pencil") { editing = plan }.tint(.blue)
        }
        .swipeActions(allowsFullSwipe: false) {
            Button("삭제", systemImage: "trash", role: .destructive) { deleting = plan }
        }
        .contextMenu { editActions(plan) }
    }

    private func planIdentity(_ plan: Workout) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: plan.exercise.symbol)
                .font(.title2)
                .frame(width: 44, height: 44)
                .foregroundStyle(MYMSStyle.accent)
                .background(MYMSStyle.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(plan.exercise.rawValue).font(.title3.bold())
                Text("\(plan.level.title) · \(plan.target)회 × \(plan.sets)세트 · 휴식 \(plan.rest)초")
                    .font(.subheadline).foregroundStyle(.secondary)
                if coach.selectedWorkoutID == plan.id {
                    Label("선택한 계획", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(MYMSStyle.accent)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func planMenu(_ plan: Workout) -> some View {
        Menu { editActions(plan) } label: {
            Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("\(plan.exercise.rawValue) 계획 관리")
    }

    @ViewBuilder private func editActions(_ plan: Workout) -> some View {
        Button("편집", systemImage: "pencil") { editing = plan }
        Button("삭제", systemImage: "trash", role: .destructive) { deleting = plan }
    }

    @ViewBuilder private func planActions(_ plan: Workout) -> some View {
        Button { prepare(plan) } label: {
            Label("운동 준비", systemImage: "arrow.right")
        }
        .mymsPrimaryButton()
        .disabled(!coach.canSelect || !store.loaded)
        .accessibilityHint("이 계획을 선택하고 운동 화면으로 이동합니다")
        Button { guide = plan } label: {
            Label("운동 방법", systemImage: "book")
        }
        .buttonStyle(.bordered)
    }

    private func prepare(_ plan: Workout) {
        guard coach.canSelect, let current = store.plans.first(where: { $0.id == plan.id }) else { return }
        coach.select(current)
        guide = nil
        tab = .workout
    }

}
