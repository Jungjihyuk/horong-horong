import SwiftUI
import Charts

/// 감정 타임라인 카드. 오전·오후는 한 그래프에서 색으로 구분하고, 하루(전반)는 따로 본다.
///
/// 셋을 한 그래프에 섞으면 «오후 → 하루» 처럼 감정이 바뀌지 않았는데 바뀐 것처럼 보이는
/// 가짜 흐름이 생긴다.
struct DiaryMoodTimelineCard: View, Equatable {
    let snapshot: DiaryInsightsSnapshot

    @State private var tab = Tab.daypart

    enum Tab: String, DiaryInsightCardTab {
        case daypart, wholeDay
        var id: String { rawValue }
        var title: String { self == .daypart ? "오전·오후" : "하루" }
        var stream: DiaryMoodStream { self == .daypart ? .daypart : .wholeDay }
    }

    nonisolated static func == (lhs: DiaryMoodTimelineCard, rhs: DiaryMoodTimelineCard) -> Bool {
        lhs.snapshot == rhs.snapshot
    }

    var body: some View {
        DiaryInsightCardShell(title: "감정 타임라인", selection: $tab) {
            DiaryMoodTimelineChart(
                points: snapshot.points(in: tab.stream),
                stream: tab.stream,
                missingIntensityCount: snapshot.missingIntensityCount(in: tab.stream)
            )
            .equatable()
        }
    }
}

/// 감정 패턴 카드. 전이·지속·원인 세 질문을 갈아 본다.
struct DiaryMoodPatternCard: View, Equatable {
    let snapshot: DiaryInsightsSnapshot

    @State private var tab = Tab.transition
    /// 패턴도 흐름을 섞지 않는다. 오전·오후 기록이 있으면 그쪽을, 없으면 하루를 본다.
    @State private var stream: DiaryMoodStream?

    enum Tab: String, DiaryInsightCardTab {
        case transition, streak, cause
        var id: String { rawValue }
        var title: String {
            switch self {
            case .transition: return "전이"
            case .streak: return "지속"
            case .cause: return "원인"
            }
        }
    }

    nonisolated static func == (lhs: DiaryMoodPatternCard, rhs: DiaryMoodPatternCard) -> Bool {
        lhs.snapshot == rhs.snapshot
    }

    var body: some View {
        DiaryInsightCardShell(title: "감정 패턴", selection: $tab) {
            if tab != .cause {
                streamPicker
            }
            switch tab {
            case .transition:
                DiaryMoodTransitionMap(
                    transitions: snapshot.transitions(in: activeStream),
                    points: snapshot.points(in: activeStream)
                )
                .equatable()
            case .streak:
                DiaryMoodStreakList(
                    summaries: snapshot.streaks(in: activeStream),
                    stream: activeStream
                )
                .equatable()
            case .cause:
                causeChart
            }
        }
    }

    private var streamPicker: some View {
        HStack(spacing: 3) {
            ForEach(DiaryMoodStream.allCases) { candidate in
                let isActive = activeStream == candidate
                Button(candidate.title) { stream = candidate }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(isActive ? PopoverChrome.accent : PopoverChrome.inkTertiary)
                    .padding(.horizontal, 7)
                    .frame(height: 19)
                    .background(
                        isActive ? PopoverChrome.accentSoft.opacity(0.55) : .clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                    .accessibilityAddTraits(isActive ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
    }

    /// 사용자가 고르기 전에는 기록이 있는 쪽을 자동으로 연다 — 빈 그래프로 맞이하지 않는다.
    private var activeStream: DiaryMoodStream {
        stream ?? (snapshot.points(in: .daypart).isEmpty ? .wholeDay : .daypart)
    }

    @ViewBuilder
    private var causeChart: some View {
        let rows = snapshot.causeDistribution
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(5)
        if rows.isEmpty {
            DiaryInsightEmpty(message: "원인을 함께 적으면 무엇이 마음을 흔드는지 보여요")
        } else {
            Chart {
                ForEach(Array(rows), id: \.key) { row in
                    BarMark(
                        x: .value("일수", row.value),
                        y: .value("원인", row.key)
                    )
                    .foregroundStyle(PopoverChrome.accent.opacity(0.75))
                    .cornerRadius(3)
                    .annotation(position: .trailing, spacing: 4) {
                        Text("\(row.value)")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(PopoverChrome.inkTertiary)
                    }
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(preset: .aligned, position: .leading) {
                    AxisValueLabel().font(.system(size: 10, design: .rounded))
                }
            }
            .frame(height: max(CGFloat(rows.count) * 26, 52))
        }
    }
}

/// 수면 인사이트 카드. «시각»(몇 시에 자고 깼는지)과 «시간»(얼마나 잤는지)은 다른 질문이다.
struct DiarySleepInsightCard: View, Equatable {
    let snapshot: DiaryInsightsSnapshot
    let axis: DiarySleepAxis

    @State private var tab = Tab.clock

    enum Tab: String, DiaryInsightCardTab {
        case clock, duration
        var id: String { rawValue }
        var title: String { self == .clock ? "시각" : "시간" }
    }

    nonisolated static func == (lhs: DiarySleepInsightCard, rhs: DiarySleepInsightCard) -> Bool {
        lhs.snapshot == rhs.snapshot && lhs.axis == rhs.axis
    }

    var body: some View {
        DiaryInsightCardShell(title: "수면", selection: $tab) {
            switch tab {
            case .clock: clockChart
            case .duration: durationChart
            }
        }
    }

    @ViewBuilder
    private var clockChart: some View {
        if snapshot.sleepWindowPoints.isEmpty {
            DiaryInsightEmpty(message: "수면 기록이 아직 없어요")
        } else {
            Chart {
                ForEach(snapshot.sleepWindowPoints) { point in
                    BarMark(
                        xStart: .value("취침", point.startFraction),
                        xEnd: .value("기상", point.endFraction),
                        y: .value("날짜", point.day, unit: .day)
                    )
                    .foregroundStyle(PopoverChrome.accent.opacity(0.7))
                    .cornerRadius(3)
                }
            }
            .chartXScale(domain: 0...1)
            .chartXAxis {
                AxisMarks(values: axis.ticks(maximumCount: 6).map(\.fraction)) { value in
                    AxisGridLine().foregroundStyle(PopoverChrome.divider.opacity(0.4))
                    AxisValueLabel {
                        if let fraction = value.as(Double.self) {
                            Text(hourLabel(atFraction: fraction))
                                .font(.system(size: 9, design: .rounded))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                        .font(.system(size: 9, design: .rounded))
                }
            }
            .frame(height: 140)

            Text("가로축 \(DiarySleepAxisText.summary(axis))")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)
        }
    }

    @ViewBuilder
    private var durationChart: some View {
        if snapshot.sleepPoints.isEmpty {
            DiaryInsightEmpty(message: "수면 기록이 아직 없어요")
        } else {
            let values = snapshot.sleepPoints.map(\.value)
            let average = values.reduce(0, +) / Double(values.count)
            Chart {
                ForEach(snapshot.sleepPoints) { point in
                    BarMark(x: .value("날짜", point.day, unit: .day), y: .value("수면", point.value))
                        .foregroundStyle(PopoverChrome.accent.opacity(0.7))
                        .cornerRadius(3)
                }
                RuleMark(y: .value("평균", average))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            .chartYScale(domain: 0...max(10, (values.max() ?? 8).rounded(.up)))
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(PopoverChrome.divider.opacity(0.4))
                    AxisValueLabel {
                        if let hours = value.as(Double.self) {
                            Text("\(Int(hours))h").font(.system(size: 9, design: .rounded))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) {
                    AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                        .font(.system(size: 9, design: .rounded))
                }
            }
            .frame(height: 128)

            Text("평균 \(DiarySleepText.duration(average))")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)
        }
    }

    private func hourLabel(atFraction fraction: Double) -> String {
        String(format: "%02d", axis.hour(atFraction: fraction))
    }
}

// MARK: - 공통 껍데기

/// 카드 안에서 갈아 끼우는 그래프 하나.
protocol DiaryInsightCardTab: Identifiable, Hashable, CaseIterable {
    var title: String { get }
}

/// 제목 + 세그먼트 + 내용. 카드 두 장이 같은 틀을 쓴다.
struct DiaryInsightCardShell<Tab: DiaryInsightCardTab, Content: View>: View where Tab.AllCases == [Tab] {
    let title: String
    @Binding var selection: Tab
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                Spacer(minLength: 0)
                HStack(spacing: 2) {
                    ForEach(Tab.allCases) { tab in
                        Button(tab.title) { selection = tab }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(selection == tab ? PopoverChrome.selectionInk : PopoverChrome.inkTertiary)
                            .padding(.horizontal, 8)
                            .frame(height: 21)
                            .background(
                                selection == tab ? PopoverChrome.selectionFill : .clear,
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                    }
                }
                .padding(2)
                .background(PopoverChrome.surfaceAlt, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            content()
        }
        .padding(12)
        .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(PopoverChrome.border, lineWidth: 0.5)
        )
    }
}

struct DiaryInsightEmpty: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(PopoverChrome.inkTertiary)
            .frame(maxWidth: .infinity, minHeight: 72)
            .multilineTextAlignment(.center)
    }
}
