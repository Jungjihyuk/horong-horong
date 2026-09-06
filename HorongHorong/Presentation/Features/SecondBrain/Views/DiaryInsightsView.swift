import SwiftUI
import Charts

/// 기간을 넓혀 보는 인사이트 시트.
///
/// **감정에 점수를 매기지 않는다.** 예전에는 «밝음 +3 · 화남 −2» 라는 등급을 y축으로 썼다.
/// 그건 기록이 아니라 평가였고, 그마저 비대칭이라 −3 은 나올 수 없었다.
/// 이제 y축은 강도이고, 감정이 어떻게 «변하는지» 는 전이 지도와 지속이 답한다.
struct DiaryInsightsView: View {
    @State private var viewModel: DiaryInsightsViewModel
    @State private var selectedStream: DiaryMoodStream?
    @Environment(\.dismiss) private var dismiss

    private let axis: DiarySleepAxis

    init(repository: DiaryRepository, referenceDate: Date, axis: DiarySleepAxis = .default) {
        self.axis = axis
        _viewModel = State(initialValue: DiaryInsightsViewModel(
            repository: repository,
            referenceDate: referenceDate
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    timelineCard(.daypart)
                    timelineCard(.wholeDay)
                    transitionCard
                    streakCard
                    causeCard
                    sleepClockCard
                    sleepDurationCard
                }
                .padding(22)
            }
        }
        .background(PopoverChrome.surface)
        .onAppear {
            viewModel.sleepAxis = axis
            viewModel.reload()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("마음과 잠의 기록")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                Text("\(InsightsDateText.period(viewModel.snapshot.start, end: viewModel.snapshot.end))")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
            }
            Spacer()
            HStack(spacing: 2) {
                ForEach(DiaryInsightsRange.allCases) { range in
                    // `.buttonStyle(.plain)` 이 없으면 macOS 기본 스타일이 라벨을 강조색으로 칠하고
                    // 바깥의 `foregroundStyle` 을 무시한다 — 고른 칸은 주황 위 주황이 되어 글자가 사라진다.
                    Button { viewModel.range = range } label: {
                        Text(range.title)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(viewModel.range == range ? PopoverChrome.selectionInk : PopoverChrome.inkSecondary)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(
                                viewModel.range == range ? PopoverChrome.selectionFill : .clear,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(viewModel.range == range ? .isSelected : [])
                }
            }
            .padding(3)
            .background(PopoverChrome.surfaceAlt, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            // 시트를 닫는 길이 esc 뿐이면 키보드를 안 쓰는 사람은 갇힌다.
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .frame(width: 26, height: 26)
                    .background(PopoverChrome.card, in: Circle())
                    .overlay(Circle().stroke(PopoverChrome.border, lineWidth: 0.5))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("닫기")
            .accessibilityLabel("인사이트 닫기")
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(PopoverChrome.surfaceAlt)
    }

    // MARK: - 감정

    private func timelineCard(_ stream: DiaryMoodStream) -> some View {
        insightsCard(
            title: stream == .daypart ? "감정 타임라인 · 오전/오후" : "감정 타임라인 · 하루",
            subtitle: stream == .daypart
                ? "색은 오전인지 오후인지, 이모지는 어떤 감정이었는지를 말합니다"
                : "그날 전체를 한마디로 적은 기록"
        ) {
            DiaryMoodTimelineChart(
                points: viewModel.snapshot.points(in: stream),
                stream: stream,
                missingIntensityCount: viewModel.snapshot.missingIntensityCount(in: stream),
                height: 220
            )
            .equatable()
            distributionRows(viewModel.snapshot.moodDistribution, empty: "분포를 계산할 기록이 없어요")
        }
    }

    private var transitionCard: some View {
        insightsCard(title: "감정 전이 지도", subtitle: "어떤 감정 뒤에 어떤 감정이 왔는가") {
            streamPicker
            DiaryMoodTransitionMap(
                transitions: viewModel.snapshot.transitions(in: patternStream),
                points: viewModel.snapshot.points(in: patternStream),
                height: 320
            )
            .equatable()
        }
    }

    private var streakCard: some View {
        insightsCard(title: "감정 지속", subtitle: "한 번 찾아오면 얼마나 머무는가") {
            DiaryMoodStreakList(
                summaries: viewModel.snapshot.streaks(in: patternStream),
                stream: patternStream
            )
            .equatable()
        }
    }

    /// 전이와 지속은 같은 흐름을 봐야 한다 — 따로 고르게 하면 두 카드가 서로 다른 이야기를 한다.
    private var streamPicker: some View {
        HStack(spacing: 3) {
            ForEach(DiaryMoodStream.allCases) { candidate in
                let isActive = patternStream == candidate
                Button(candidate.title) { selectedStream = candidate }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(isActive ? PopoverChrome.selectionInk : PopoverChrome.inkSecondary)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(
                        isActive ? PopoverChrome.selectionFill : .clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .accessibilityAddTraits(isActive ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(3)
        .background(PopoverChrome.surfaceAlt, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var patternStream: DiaryMoodStream {
        selectedStream ?? (viewModel.snapshot.points(in: .daypart).isEmpty ? .wholeDay : .daypart)
    }

    private var causeCard: some View {
        insightsCard(title: "무엇이 마음을 흔들었나", subtitle: "감정과 함께 고른 원인") {
            distributionRows(viewModel.snapshot.causeDistribution, empty: "원인을 함께 적으면 여기 쌓여요")
        }
    }

    // MARK: - 수면

    private var sleepClockCard: some View {
        insightsCard(
            title: "취침·기상 시각",
            subtitle: "가로축 \(DiarySleepAxisText.summary(axis))"
        ) {
            if viewModel.snapshot.sleepWindowPoints.isEmpty {
                emptyChart("수면 기록이 아직 없어요")
            } else {
                Chart {
                    ForEach(viewModel.snapshot.sleepWindowPoints) { point in
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
                    AxisMarks(values: axis.ticks(maximumCount: 12).map(\.fraction)) { value in
                        AxisGridLine().foregroundStyle(PopoverChrome.divider.opacity(0.45))
                        AxisValueLabel {
                            if let fraction = value.as(Double.self) {
                                Text("\(axis.hour(atFraction: fraction))시")
                            }
                        }
                    }
                }
                .frame(height: 240)
            }
        }
    }

    private var sleepDurationCard: some View {
        insightsCard(title: "수면 시간", subtitle: "하루에 잔 길이와 기간 평균") {
            if viewModel.snapshot.sleepPoints.isEmpty {
                emptyChart("수면 기록이 아직 없어요")
            } else {
                let values = viewModel.snapshot.sleepPoints.map(\.value)
                let average = values.reduce(0, +) / Double(values.count)
                Chart {
                    ForEach(viewModel.snapshot.sleepPoints) { point in
                        BarMark(x: .value("날짜", point.day, unit: .day), y: .value("수면", point.value))
                            .foregroundStyle(PopoverChrome.accent.opacity(0.7))
                            .cornerRadius(3)
                    }
                    RuleMark(y: .value("평균", average))
                        .foregroundStyle(PopoverChrome.inkSecondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                }
                .chartYScale(domain: 0...14)
                .chartYAxis {
                    AxisMarks(values: [0, 4, 8, 12, 14]) { value in
                        AxisGridLine().foregroundStyle(PopoverChrome.divider.opacity(0.45))
                        AxisValueLabel {
                            if let hours = value.as(Double.self) {
                                Text(DiarySleepText.duration(hours))
                            }
                        }
                    }
                }
                .frame(height: 220)

                HStack(spacing: 18) {
                    metric("평균", value: DiarySleepText.duration(average))
                    metric("가장 짧은 날", value: DiarySleepText.duration(values.min() ?? 0))
                    metric("가장 긴 날", value: DiarySleepText.duration(values.max() ?? 0))
                }
            }
        }
    }

    // MARK: - 공통

    private func insightsCard<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
            }
            content()
        }
        .padding(16)
        .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(PopoverChrome.border, lineWidth: 0.7))
    }

    private func emptyChart(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(PopoverChrome.inkTertiary)
            .frame(maxWidth: .infinity, minHeight: 100)
    }

    private func distributionRows(_ values: [String: Int], empty: String) -> some View {
        let rows = values.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        return VStack(alignment: .leading, spacing: 6) {
            if rows.isEmpty {
                Text(empty)
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkTertiary)
            } else {
                ForEach(rows, id: \.key) { item in
                    HStack(spacing: 8) {
                        Text(item.key)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(PopoverChrome.inkSecondary)
                        GeometryReader { proxy in
                            Capsule()
                                .fill(PopoverChrome.accentSoft)
                                .frame(width: proxy.size.width * CGFloat(item.value) / CGFloat(max(1, rows[0].value)), height: 6)
                        }
                        .frame(height: 6)
                        Text("\(item.value)일")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(PopoverChrome.inkTertiary)
                    }
                }
            }
        }
    }

    private func metric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(PopoverChrome.inkTertiary)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.ink)
        }
    }
}

@MainActor
private enum InsightsDateText {
    static func period(_ start: Date, end: Date) -> String {
        "\(formatter.string(from: start)) ~ \(formatter.string(from: end.addingTimeInterval(-86_400)))"
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일"
        return formatter
    }()
}
