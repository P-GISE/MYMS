import SwiftUI

extension WorkoutHome {
    var history: some View {
        NavigationStack {
            List {
                Section { WorkoutStatisticsView(records: store.records) }
                if store.records.isEmpty {
                    ContentUnavailableView("운동 기록이 없어요", systemImage: "clock", description: Text("센서로 측정한 운동이 여기에 저장됩니다."))
                }
                ForEach(store.records) { record in
                    NavigationLink {
                        Form {
                            Section("운동 결과") {
                                LabeledContent("측정 방식", value: record.measurementSource ?? "ToF 거리")
                                LabeledContent("운동", value: record.workout.exercise.rawValue)
                                LabeledContent("난이도", value: record.workout.level.title)
                                LabeledContent("유효 횟수", value: "\(record.reps)회")
                                LabeledContent("완료 세트", value: "\(record.sets) / \(record.workout.sets)")
                                LabeledContent("경과 시간", value: "\(record.seconds)초")
                                LabeledContent("획득 포인트", value: "\(record.points) P")
                            }
                            if let environment = record.environment {
                                Section("측정 환경") {
                                    LabeledContent("환경 기록 시각", value: environment.measuredAt.formatted(date: .abbreviated, time: .standard))
                                    LabeledContent("운동기구", value: environment.equipment?.rawValue ?? "미선택")
                                    LabeledContent("장소", value: environment.place?.rawValue ?? "미선택")
                                    LabeledContent("신발", value: environment.footwear?.rawValue ?? "미선택")
                                    if let value = environment.brightnessRaw {
                                        LabeledContent("밝기 원시값", value: "\(value.formatted(.number.precision(.fractionLength(0)))) count")
                                    }
                                    LabeledContent("밝기 비교", value: environment.brightnessDescription)
                                    if let value = environment.brightnessReference {
                                        LabeledContent("밝기 기준값", value: "\(value.formatted(.number.precision(.fractionLength(0)))) count")
                                    }
                                    if let value = environment.inclineDegrees {
                                        LabeledContent("기준면과의 각도", value: "\(value.formatted(.number.precision(.fractionLength(2)))) °")
                                    }
                                    LabeledContent("경사 비교", value: environment.inclineDescription)
                                    if environment.equipment != nil || environment.place != nil || environment.footwear != nil {
                                        Text("운동 시작 시 저장한 환경입니다. 밝기는 조도(lux)가 아닌 원시값이며, 경사 구분은 3°를 초기 기준으로 사용합니다.")
                                            .font(.footnote).foregroundStyle(.secondary)
                                    }
                                }
                                if environment.temperatureCelsius != nil || environment.humidityPercent != nil || environment.pressureKPa != nil {
                                    Section("이전 형식의 환경 기록") {
                                        if let value = environment.temperatureCelsius {
                                            LabeledContent("온도", value: "\(value.formatted(.number.precision(.fractionLength(1)))) °C")
                                        }
                                        if let value = environment.humidityPercent {
                                            LabeledContent("습도", value: "\(value.formatted(.number.precision(.fractionLength(1)))) %")
                                        }
                                        if let value = environment.pressureKPa {
                                            LabeledContent("기압", value: "\(value.formatted(.number.precision(.fractionLength(2)))) kPa")
                                        }
                                    }
                                }
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
                            if record.measurementSource == "IMU 동작 테스트" {
                                Text("IMU 동작 테스트 · 운동 정확도 미검증").font(.caption).foregroundStyle(.secondary)
                            }
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
