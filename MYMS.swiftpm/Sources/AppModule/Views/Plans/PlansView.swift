import SwiftUI

extension WorkoutHome {
    var plans: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("누적 포인트").font(.subheadline)
                            Text("\(store.points) P").font(.largeTitle.bold()).monospacedDigit()
                        }
                        Spacer()
                        Image(systemName: "bolt.fill").font(.largeTitle)
                    }
                    .padding(.vertical, 10)
                    .foregroundStyle(.white)
                    .listRowBackground(Color(red: 0.05, green: 0.29, blue: 0.22))
                }
                Section("오늘의 운동") {
                    ForEach(store.plans) { plan in
                        Button {
                            guide = plan
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: plan.exercise.symbol).foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(plan.exercise.rawValue).font(.headline).foregroundStyle(.primary)
                                    Text("\(plan.level.title) · \(plan.target)회 × \(plan.sets)세트")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("운동 방법").font(.subheadline.weight(.medium)).foregroundStyle(.tint)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .leading) {
                            Button("편집", systemImage: "pencil") { editing = plan }.tint(.blue)
                        }
                        .swipeActions(allowsFullSwipe: false) {
                            Button("삭제", systemImage: "trash", role: .destructive) { deleting = plan }
                        }
                        .contextMenu {
                            Button("편집", systemImage: "pencil") { editing = plan }
                            Button("삭제", systemImage: "trash", role: .destructive) { deleting = plan }
                        }
                    }
                    if store.plans.isEmpty { Text("추가 버튼으로 운동 계획을 만드세요.").foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("운동 계획")
            .toolbar { Button("추가", systemImage: "plus") { editing = Workout() }.disabled(!store.loaded) }
            .sheet(item: $guide) { plan in
                ExerciseGuide(plan: plan, canSelect: coach.canSelect) {
                    coach.select(plan)
                    guide = nil
                    tab = 1
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
}
