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
        let exerciseRecords = records.filter { $0.measurementSource != "IMU 동작 테스트" && $0.date <= now && $0.reps > 0 }
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
        VStack(alignment: .leading, spacing: 12) {
            Text("이번 주 운동 횟수").font(.headline)
            Chart(stats.week) { day in
                BarMark(x: .value("날짜", day.date, unit: .day), y: .value("횟수", day.reps))
            }
            .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.abbreviated)) } }
            .frame(height: 160)
            LabeledContent("연속 운동일", value: "\(stats.streak)일")
            LabeledContent("한 세션 최다 횟수 (PR)", value: "\(stats.personalBest)회")
            Text("연속일은 오늘 또는 어제부터 계산합니다. IMU 동작 테스트는 운동 통계에서 제외합니다.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}
