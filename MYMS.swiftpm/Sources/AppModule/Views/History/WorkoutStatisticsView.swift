import SwiftUI
import Charts

struct WorkoutStatistics {
    enum Source: String, CaseIterable {
        case exercise = "실제 운동"
        case simulation = "시연"

        func records(from records: [WorkoutRecord]) -> [WorkoutRecord] {
            records.filter { self == .simulation ? $0.isSimulation : !$0.isLocalOnly }
        }
    }

    struct Day: Identifiable {
        let date: Date
        let reps: Int
        var id: Date { date }
    }

    let week: [Day]
    let streak: Int
    let personalBest: Int

    init(records: [WorkoutRecord], source: Source = .exercise, now: Date = Date(), calendar: Calendar = .current) {
        let exerciseRecords = source.records(from: records).filter { $0.date <= now && $0.reps > 0 }
        let totals = Dictionary(grouping: exerciseRecords, by: { calendar.startOfDay(for: $0.date) })
            .mapValues { $0.reduce(0) { $0 + $1.reps } }
        let today = calendar.startOfDay(for: now)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        week = (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            return Day(date: day, reps: totals[day] ?? 0)
        }
        var day = totals[today] != nil ? today : calendar.date(byAdding: .day, value: -1, to: today)
        var count = 0
        while let current = day, totals[current] != nil {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: current)
        }
        streak = count
        personalBest = exerciseRecords.map(\.reps).max() ?? 0
    }
}

struct WorkoutStatisticsView: View {
    let records: [WorkoutRecord]
    @Binding var source: WorkoutStatistics.Source

    var body: some View {
        let stats = WorkoutStatistics(records: records, source: source)
        let weeklyReps = stats.week.reduce(0) { $0 + $1.reps }
        VStack(alignment: .leading, spacing: 14) {
            Picker("통계 종류", selection: $source) {
                ForEach(WorkoutStatistics.Source.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("historyStatisticsSource")

            VStack(alignment: .leading, spacing: 3) {
                Label(source == .simulation ? "이번 주 시연 횟수" : "이번 주 유효 횟수", systemImage: "chart.bar.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Text("\(weeklyReps)회")
                    .font(.largeTitle.bold()).monospacedDigit()
            }
            .accessibilityElement(children: .combine)

            Chart(stats.week) { day in
                BarMark(x: .value("날짜", day.date, unit: .day),
                        y: .value("횟수", day.reps), width: .ratio(0.55))
                    .foregroundStyle(.tint)
                    .cornerRadius(4)
                    .annotation(position: .top) {
                        if day.reps > 0 { Text("\(day.reps)").font(.caption2).monospacedDigit() }
                    }
                    .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide)))
                    .accessibilityValue("\(day.reps)회")
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                }
            }
            .frame(height: 132)

            if weeklyReps == 0 {
                Text(source == .simulation ? "이번 주 시연 횟수가 0회입니다. 가상 동작 후 종료하면 그래프에 반영됩니다." : "이번 주 실제 운동 횟수가 0회입니다. 시연 기록은 시연 탭에서 확인하세요.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            LabeledContent(source == .simulation ? "연속 시연일" : "연속 운동일", value: "\(stats.streak)일")
            LabeledContent("한 번에 가장 많이 한 횟수", value: "\(stats.personalBest)회")
            Text(source == .simulation
                 ? "시연 기록만 표시합니다. 시연은 포인트와 실제 운동 통계에 반영되지 않습니다."
                 : "연속 운동일은 오늘이나 어제부터 셉니다. 시연과 IMU 동작 테스트는 제외됩니다.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}
