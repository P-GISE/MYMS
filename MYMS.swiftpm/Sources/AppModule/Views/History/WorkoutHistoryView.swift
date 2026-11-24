import SwiftUI

extension WorkoutHome {
    var history: some View {
        NavigationStack {
            GeometryReader { geometry in
                if store.loaded && store.records.isEmpty {
                    ContentUnavailableView {
                        Label("첫 기록을 기다리고 있어요", systemImage: "clock")
                    } description: {
                        Text("운동이나 시연을 종료하면 횟수와 세트를 여기서 확인할 수 있어요.")
                    } actions: {
                        Button("운동 화면으로 이동") { tab = .workout }
                            .mymsPrimaryButton()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !store.records.isEmpty {
                    if geometry.size.width >= 760 && !typeSize.isAccessibilitySize {
                        HStack(alignment: .top, spacing: 0) {
                            ScrollView {
                                WorkoutStatisticsView(records: store.records)
                                    .padding(20).mymsCard()
                                    .padding(.leading, 24).padding(.vertical, 12)
                            }
                            .frame(width: min(400, geometry.size.width * 0.4))
                            recordsList(includesStatistics: false)
                        }
                    } else {
                        recordsList(includesStatistics: true)
                    }
                }
            }
            .background(MYMSStyle.canvas)
            .navigationTitle("운동 기록")
            .confirmationDialog(deletingRecord?.points == 0 ? "이 기록을 삭제할까요?" : "기록과 적립 포인트를 삭제할까요?", isPresented: Binding(
                get: { deletingRecord != nil }, set: { if !$0 { deletingRecord = nil } }
            ), titleVisibility: .visible) {
                Button("삭제", role: .destructive) {
                    if let deletingRecord { store.records.removeAll { $0.id == deletingRecord.id } }
                    deletingRecord = nil
                }
            }
        }
    }
    private func recordsList(includesStatistics: Bool) -> some View {
        List {
            if includesStatistics {
                Section {
                    DisclosureGroup("이번 주 운동 통계") {
                        WorkoutStatisticsView(records: store.records)
                    }
                    .listRowBackground(MYMSStyle.surface)
                }
            }
            Section("최근 운동 기록") {
                ForEach(store.records) { record in
                    NavigationLink { recordDetail(record) } label: {
                        recordSummary(record)
                    }
                    .listRowBackground(MYMSStyle.surface)
                    .swipeActions(allowsFullSwipe: false) {
                        Button("삭제", systemImage: "trash", role: .destructive) { deletingRecord = record }
                    }
                    .contextMenu {
                        Button("기록 삭제", systemImage: "trash", role: .destructive) { deletingRecord = record }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func recordSummary(_ record: WorkoutRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: record.workout.exercise.symbol)
                .font(.title2)
                .frame(width: 44, height: 44)
                .foregroundStyle(MYMSStyle.accent)
                .background(MYMSStyle.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(record.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
                Text(record.workout.exercise.rawValue).font(.headline)
                Text("\(record.reps)회 · \(record.sets)세트 · \(record.points) P")
                    .font(.subheadline).monospacedDigit()
                if record.isSimulation {
                    Label("시연 · 통계 제외", systemImage: "play.rectangle")
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                } else if record.isLocalOnly {
                    Label("IMU 동작 테스트 · 통계 제외", systemImage: "waveform")
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 5)
    }

    private func recordDetail(_ record: WorkoutRecord) -> some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(record.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline.weight(.semibold)).foregroundStyle(MYMSStyle.lime)
                    Text(record.workout.exercise.rawValue).font(.title.bold())
                    Text("\(record.reps)회 · \(record.sets)세트 · \(record.seconds)초")
                        .font(.headline).monospacedDigit()
                }
                .padding(.vertical, 8).foregroundStyle(.white)
                .listRowBackground(MYMSStyle.ink)
            }
            Section("측정 결과") {
                LabeledContent("측정 방식", value: record.measurementSource ?? "ToF 거리")
                LabeledContent("난이도", value: record.workout.level.title)
                LabeledContent(record.isSimulation ? "시연 횟수" : "유효 횟수", value: "\(record.reps)회")
                LabeledContent("완료 세트", value: "\(record.sets) / \(record.workout.sets)")
                LabeledContent("획득 포인트", value: "\(record.points) P")
                if record.isSimulation {
                    Text("시연 기록은 이 기기에 저장하며 포인트와 실제 운동 통계에는 포함하지 않습니다.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
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
        .scrollContentBackground(.hidden)
        .background(MYMSStyle.canvas)
    }

}
