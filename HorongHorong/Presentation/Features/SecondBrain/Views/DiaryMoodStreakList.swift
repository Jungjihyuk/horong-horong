import SwiftUI

/// 감정 지속. «한 번 오면 얼마나 머무는가».
struct DiaryMoodStreakList: View, Equatable {
    let summaries: [DiaryMoodStreakSummary]
    let stream: DiaryMoodStream

    nonisolated static func == (lhs: DiaryMoodStreakList, rhs: DiaryMoodStreakList) -> Bool {
        lhs.summaries == rhs.summaries && lhs.stream == rhs.stream
    }

    var body: some View {
        if summaries.isEmpty {
            DiaryInsightEmpty(message: "감정 기록이 쌓이면 얼마나 머무는지 보여요")
        } else {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(summaries) { summary in
                    row(summary)
                }
                if let longest = summaries.first, longest.averageLength > 1 {
                    Text("\(longest.group.shortTitle)은(는) 한번 오면 오래 머무릅니다")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                        .padding(.top, 2)
                }
            }
        }
    }

    private func row(_ summary: DiaryMoodStreakSummary) -> some View {
        HStack(spacing: 6) {
            Text(summary.group.emoji).font(.system(size: 12))
            Text(summary.group.shortTitle)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(PopoverChrome.ink)
                .lineLimit(1)
                .frame(width: 50, alignment: .leading)

            GeometryReader { proxy in
                Capsule()
                    .fill(summary.group.chartColor.opacity(0.65))
                    .frame(width: max(proxy.size.width * ratio(summary), 3), height: 6)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(minWidth: 24, maxWidth: .infinity)
            .frame(height: 14)

            // **글자가 먼저 자리를 잡는다.** 남는 폭을 막대가 가져가야 «평균 1.0일 · 최장 / 1일» 처럼
            // 두 줄로 접히지 않는다.
            Text(unitText(summary))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(PopoverChrome.inkTertiary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(summary.group.title), \(unitText(summary))")
    }

    /// 막대는 «평균» 을 최장 평균 기준으로 잰다. 최장값으로 재면 한 번 길게 이어진 감정이
    /// 나머지를 전부 눌러 버린다.
    private func ratio(_ summary: DiaryMoodStreakSummary) -> Double {
        let maximum = summaries.map(\.averageLength).max() ?? 1
        guard maximum > 0 else { return 0 }
        return summary.averageLength / maximum
    }

    /// 오전·오후 흐름은 관측 하나가 **반나절**이다. 그대로 세면 «1칸» 이 되는데, 하루 흐름의
    /// «1일» 과 나란히 놓으면 같은 길이처럼 읽힌다. 두 탭을 견줄 수 있도록 **양쪽 다 일로** 옮긴다.
    private var observationsPerDay: Double { stream == .daypart ? 2 : 1 }

    private func unitText(_ summary: DiaryMoodStreakSummary) -> String {
        let average = summary.averageLength / observationsPerDay
        let longest = Double(summary.longestLength) / observationsPerDay
        return "평균 \(dayText(average))일 · 최장 \(dayText(longest))일"
    }

    /// 0.5 는 «0.5», 2 는 «2» 로. 정수인데 «2.0일» 이라고 쓰면 눈에 걸린다.
    private func dayText(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(format: "%.1f", rounded)
    }
}
