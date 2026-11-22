import SwiftUI

extension WorkoutHome {
    var history: some View {
        NavigationStack {
            List {
                if store.records.isEmpty {
                    ContentUnavailableView("운동 기록이 없어요", systemImage: "clock", description: Text("센서로 측정한 운동이 여기에 저장됩니다."))
                }
                ForEach(store.records) { record in
                    NavigationLink {
                        Form {
                            Section("운동 결과") {
                                LabeledContent("운동", value: record.workout.exercise.rawValue)
                                LabeledContent("난이도", value: record.workout.level.title)
                                LabeledContent("유효 횟수", value: "\(record.reps)회")
                                LabeledContent("완료 세트", value: "\(record.sets) / \(record.workout.sets)")
                                LabeledContent("경과 시간", value: "\(record.seconds)초")
                                LabeledContent("획득 포인트", value: "\(record.points) P")
                            }
                            Section("메모") {
                                TextField("운동 메모", text: Binding(
                                    get: { store.records.first { $0.id == record.id }?.note ?? "" },
                                    set: { note in
                                        if let index = store.records.firstIndex(where: { $0.id == record.id }) {
                                            store.records[index].note = note
                                        }
                                    }
                                ), axis: .vertical)
                            }
                        }
                        .navigationTitle("운동 결과")
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.workout.exercise.rawValue).font(.headline)
                            Text(record.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text("\(record.workout.level.title) · \(record.reps)회 · \(record.points) P")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(allowsFullSwipe: false) {
                        Button("삭제", systemImage: "trash", role: .destructive) { deletingRecord = record }
                    }
                }
            }
            .navigationTitle("운동 기록")
            .confirmationDialog("기록과 적립 포인트를 삭제할까요?", isPresented: Binding(
                get: { deletingRecord != nil }, set: { if !$0 { deletingRecord = nil } }
            ), titleVisibility: .visible) {
                Button("삭제", role: .destructive) {
                    if let deletingRecord { store.records.removeAll { $0.id == deletingRecord.id } }
                    deletingRecord = nil
                }
            }
        }
    }
}
