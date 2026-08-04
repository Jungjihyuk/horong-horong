import Charts
import SwiftData
import SwiftUI

/// 몰입 상세 아래에 붙는 "기준을 얼마나 지키고 있나" 카드.
///
/// 여기 몰입도(%)는 설정 → 몰입의 그 숫자다. 같은 화면 위쪽의 **몰입 점수(1–5)** 는
/// 세션이 끝난 뒤 직접 고른 체감이라 서로 다른 값이다. 이름을 갈라 적는 이유가 그것이다.
struct FocusNudgeTrendCard: View {
    @Environment(\.modelContext) private var modelContext

    @State private var weeks: [FocusTrendWeek] = []
    @State private var categoryPoints: [FocusCategoryTrendPoint] = []
    @State private var totalNudgeCount = 0

    private static let chartHeight: CGFloat = 150

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("기준선 지키기 추이")
                    .font(.headline)
                    .foregroundStyle(PopoverChrome.ink)
                Spacer()
                Text("최근 \(FocusTrendBuilder.weekCount)주 · 설정 → 몰입의 기준선 기준")
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
                onTargetChart
                nudgeChart
                categoryChart

                Divider()
                Text("잔소리는 몰입도가 낮을 때만 뜨므로, 잔소리 뒤에 좋아진 것처럼 보여도 "
                    + "그것만으로 효과라고 볼 수는 없어요. 달성률이 꾸준히 오르는지를 보세요.")
                    .font(.caption2)
                    .foregroundStyle(PopoverChrome.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .popoverCard(padding: 16)
        .task { load() }
    }

    // MARK: - 차트

    private var onTargetChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("주간 기준선 달성률")
                .font(.callout.weight(.semibold))
                .foregroundStyle(PopoverChrome.ink)
            Text("그 주 세션 중 몰입도가 기준선 이상이었던 비율")
                .font(.caption2)
                .foregroundStyle(PopoverChrome.inkTertiary)

            Chart(weeks) { week in
                LineMark(
                    x: .value("주", week.weekStart, unit: .weekOfYear),
                    y: .value("달성률", week.onTargetRatio * 100)
                )
                .foregroundStyle(PopoverChrome.accent)
                PointMark(
                    x: .value("주", week.weekStart, unit: .weekOfYear),
                    y: .value("달성률", week.onTargetRatio * 100)
                )
                .foregroundStyle(PopoverChrome.accent)
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
            .frame(height: Self.chartHeight)
        }
    }

    private var nudgeChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("주간 잔소리 횟수")
                .font(.callout.weight(.semibold))
                .foregroundStyle(PopoverChrome.ink)
            Text(totalNudgeCount > 0
                ? "줄어들면 기준선 아래로 떨어지는 세션이 줄고 있다는 뜻이에요"
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
        let nudges = events.map { FocusNudgeRecord(firedAt: $0.firedAt, category: $0.category) }

        totalNudgeCount = nudges.count
        weeks = FocusTrendBuilder.weeks(
            samples: samples,
            nudges: nudges,
            threshold: { FocusThresholdStore.shared.threshold(for: $0) }
        )
        categoryPoints = FocusTrendBuilder.categoryWeeks(samples: samples)
    }
}
