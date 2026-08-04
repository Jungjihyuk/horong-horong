import Charts
import SwiftData
import SwiftUI

/// 실제로 표시된 집중 잔소리와 세션 몰입도의 주간 추이.
struct FocusNudgeTrendCard: View {
    @Environment(\.modelContext) private var modelContext

    @State private var weeks: [FocusTrendWeek] = []
    @State private var categoryPoints: [FocusCategoryTrendPoint] = []
    @State private var totalNudgeCount = 0

    private static let chartHeight: CGFloat = 150

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("집중 잔소리 추이")
                    .font(.headline)
                    .foregroundStyle(PopoverChrome.ink)
                Spacer()
                Text("최근 \(FocusTrendBuilder.weekCount)주 · 실제 표시 기록")
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkSecondary)
            }

            if weeks.isEmpty {
                Text("아직 추이를 그릴 만큼 세션이 쌓이지 않았어요.")
                    .font(.callout)
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
            } else {
                nudgeChart
                categoryChart

                Divider()
                Text("횟수는 호로롱이가 화면에 실제로 나타난 경우만 셉니다. 설정을 바꿔도 과거 횟수는 다시 계산하지 않습니다.")
                    .font(.caption2)
                    .foregroundStyle(PopoverChrome.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .popoverCard(padding: 16)
        .task { load() }
    }

    // MARK: - 차트

    private var nudgeChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("주간 잔소리 횟수")
                .font(.callout.weight(.semibold))
                .foregroundStyle(PopoverChrome.ink)
            Text(totalNudgeCount > 0
                ? "말풍선이 실제로 표시된 횟수입니다"
                : "아직 잔소리를 들은 기록이 없어요")
                .font(.caption2)
                .foregroundStyle(PopoverChrome.inkTertiary)

            Chart(weeks) { week in
                BarMark(
                    x: .value("주", week.weekStart, unit: .weekOfYear),
                    y: .value("횟수", week.nudgeCount)
                )
                .foregroundStyle(PopoverChrome.accent.opacity(0.7))
                .cornerRadius(2)
            }
            .chartYAxis {
                AxisMarks(position: .trailing)
            }
            .frame(height: Self.chartHeight)
        }
    }

    private var categoryChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("카테고리별 몰입도")
                .font(.callout.weight(.semibold))
                .foregroundStyle(PopoverChrome.ink)
            Text("어떤 일에서 무너지는지 보여줍니다")
                .font(.caption2)
                .foregroundStyle(PopoverChrome.inkTertiary)

            Chart(categoryPoints) { point in
                LineMark(
                    x: .value("주", point.weekStart, unit: .weekOfYear),
                    y: .value("몰입도", point.meanScore * 100)
                )
                .foregroundStyle(by: .value("카테고리", point.category))
                PointMark(
                    x: .value("주", point.weekStart, unit: .weekOfYear),
                    y: .value("몰입도", point.meanScore * 100)
                )
                .foregroundStyle(by: .value("카테고리", point.category))
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(position: .trailing, values: [0, 50, 100]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let percent = value.as(Int.self) { Text("\(percent)%") }
                    }
                }
            }
            .chartLegend(position: .bottom, spacing: 8)
            .frame(height: Self.chartHeight)
        }
    }

    // MARK: - 데이터

    private func load() {
        let days = FocusTrendBuilder.weekCount * 7
        let samples = FocusScoreHistory.samples(days: days, modelContext: modelContext)

        guard let periodStart = Calendar.current.date(
            byAdding: .day, value: -days, to: Date()
        ) else { return }
        let events = (try? modelContext.fetch(
            FetchDescriptor<FocusNudgeEvent>(
                predicate: #Predicate { $0.firedAt >= periodStart },
                sortBy: [SortDescriptor(\.firedAt)]
            )
        )) ?? []
        let nudgeDates = events.map(\.firedAt)

        totalNudgeCount = nudgeDates.count
        weeks = FocusTrendBuilder.weeks(
            samples: samples,
            nudgeDates: nudgeDates
        )
        categoryPoints = FocusTrendBuilder.categoryWeeks(samples: samples)
    }
}
