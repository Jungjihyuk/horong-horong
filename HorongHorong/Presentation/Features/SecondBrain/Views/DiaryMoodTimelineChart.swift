import SwiftUI
import Charts

/// 감정 타임라인. x = 시간, y = 강도.
///
/// **감정에 점수를 매기지 않는다.** 예전 y축은 «밝음 +3 · 화남 −2» 라는 등급이었다. 지금 y축은
/// 그 감정이 얼마나 강했는지만 말하고, 무엇이었는지는 점 위 이모지가 말한다.
struct DiaryMoodTimelineChart: View, Equatable {
    let points: [DiaryMoodPoint]
    let stream: DiaryMoodStream
    /// 강도를 적지 않아 그리지 못한 기록 수.
    let missingIntensityCount: Int
    var height: CGFloat = 140

    nonisolated static func == (lhs: DiaryMoodTimelineChart, rhs: DiaryMoodTimelineChart) -> Bool {
        lhs.points == rhs.points
            && lhs.stream == rhs.stream
            && lhs.missingIntensityCount == rhs.missingIntensityCount
            && lhs.height == rhs.height
    }

    var body: some View {
        if drawable.isEmpty {
            DiaryInsightEmpty(message: emptyMessage)
        } else {
            Chart {
                ForEach(drawable) { point in
                    PointMark(
                        x: .value("시각", point.timestamp),
                        y: .value("강도", point.intensity ?? 0)
                    )
                    .foregroundStyle(point.slot.chartHue)
                    .symbolSize(70)
                    .annotation(position: .top, spacing: 2) {
                        Text(point.mood.emoji).font(.system(size: 10))
                    }
                }
            }
            .chartYScale(domain: 0.5...5.5)
            .chartYAxis {
                AxisMarks(values: Array(DiaryMoodIntensity.range)) { value in
                    AxisGridLine().foregroundStyle(PopoverChrome.divider.opacity(0.4))
                    AxisValueLabel {
                        if let level = value.as(Int.self) {
                            Text("\(level)").font(.system(size: 9, design: .rounded)).monospacedDigit()
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                        .font(.system(size: 9, design: .rounded))
                }
            }
            .frame(height: height)

            footer
        }
    }

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if stream == .daypart {
                HStack(spacing: 12) {
                    ForEach([DiaryMoodSlot.morning, .afternoon]) { slot in
                        HStack(spacing: 5) {
                            Circle().fill(slot.chartHue).frame(width: 7, height: 7)
                            Text(slot.title)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(PopoverChrome.inkSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            // 없는 강도를 «보통» 으로 채우면 적지 않은 날이 적은 날처럼 보인다. 대신 몇 개가
            // 빠졌는지 밝힌다.
            if missingIntensityCount > 0 {
                Text("강도를 적지 않은 \(missingIntensityCount)개는 표시되지 않았어요")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
            }
        }
    }

    private var drawable: [DiaryMoodPoint] {
        points.filter { $0.intensity != nil }
    }

    private var emptyMessage: String {
        guard missingIntensityCount > 0 else {
            return stream == .daypart ? "오전·오후 감정 기록이 아직 없어요" : "하루 감정 기록이 아직 없어요"
        }
        return "강도를 함께 적으면 흐름이 보여요 (\(missingIntensityCount)개 대기 중)"
    }
}
