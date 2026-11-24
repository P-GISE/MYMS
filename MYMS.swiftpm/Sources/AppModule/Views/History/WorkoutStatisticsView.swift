import SwiftUI
import Charts

struct WorkoutStatistics {
    struct Day: Identifiable {
        let date: Date
        let reps: Int
        var id: Date { date }
    }

    let week: [Day]
    let streak: Int
    let personalBest: Int

    init(records: [WorkoutRecord], now: Date = Date(), calendar: Calendar = .current) {
        let exerciseRecords = records.filter { !$0.isLocalOnly && $0.date <= now && $0.reps > 0 }
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

    var body: some View {
        let stats = WorkoutStatistics(records: records)
        let weeklyReps = stats.week.reduce(0) { $0 + $1.reps }
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Label("이번 주 유효 횟수", systemImage: "chart.bar.fill")
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
                    .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide)))
                    .accessibilityValue("\(day.reps)회")
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                }
            }
            .frame(height: 132)

            Divider()
            LabeledContent("연속 운동일", value: "\(stats.streak)일")
            LabeledContent("한 번에 가장 많이 한 횟수", value: "\(stats.personalBest)회")
            Text("연속 운동일은 오늘이나 어제부터 셉니다. 시연과 IMU 동작 테스트는 통계에서 제외됩니다.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}
