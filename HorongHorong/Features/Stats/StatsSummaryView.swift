import AppKit
import SwiftUI

/*
 메뉴바 팝오버에서 오늘·이번 주의 활동 및 집중 통계를 요약해 보여준다.

 이 파일의 책임
 - 카테고리별 사용 시간·집중 상태·전환 횟수·최장 세션과 주간 추이를 카드와 차트로 표시한다.
 - 저장소가 집계한 카테고리별 사용 시간과 집중 상태를 팝오버에 표시한다.
 - 오늘/이번 주 범위를 전환하고 상세 통계 창을 열며, 완료된 전날의 일별 요약 확정을 요청한다.

 이 파일의 책임이 아닌 것
 - 앱 사용 구간과 집중 세션의 원본 기록 수집은 Tracker와 `TimerManager`가 담당한다.
 - 날짜 경계 처리와 포모도로 시간의 집중 카테고리 귀속은 저장소가 담당한다.
 - 타임라인 버킷·집중 요약 계산은 `TimelineAnalytics`, 주의 흐름 판정은 Attention 분석 타입들이 담당한다.
 - 완료된 날짜의 일별 요약 확정은 저장소가 담당한다.
 - 전체 기간 탐색과 상세 분석 화면은 통계 상세 창이 담당한다.

 조회와 집계는 `StatsSummaryViewModel` 뒤의 저장소에서 수행한다.
 */

struct CategoryUsage: Identifiable {
    let id = UUID()
    let category: String
    let emoji: String
    let color: Color
    let durationSeconds: Int

    var hours: Double {
        Double(durationSeconds) / 3600.0
    }

    var formattedDuration: String {
        let h = durationSeconds / 3600
        let m = (durationSeconds % 3600) / 60
        return "\(h)h \(m)m"
    }
}

private enum StatsSummaryScope: String, CaseIterable, Identifiable {
    case today = "오늘"
    case week = "이번 주"

    var id: String { rawValue }
}

struct StatsSummaryView: View {
    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "E"
        return formatter
    }()

    @Environment(\.openWindow) private var openWindow
    @Environment(\.appearanceDensity) private var appearanceDensity
    @Environment(AppState.self) private var appState
    @State private var viewModel: StatsSummaryViewModel
    @State private var hoveredScope: StatsSummaryScope?
    @State private var scope: StatsSummaryScope = .today
    @State private var hostWindow: NSWindow?
    private let referenceDate: Date

    init(repository: StatsSummaryRepository, referenceDate: Date = Date()) {
        self.referenceDate = referenceDate
        _viewModel = State(initialValue: StatsSummaryViewModel(repository: repository))
    }

    var body: some View {
        VStack(spacing: 12) {
            scopePicker
            ScrollView {
                Group {
                    if scope == .today, categoryUsages.isEmpty {
                        // 기록이 없는 콜드스타트에서도 시작 유도 문구는 보여준다.
                        VStack(spacing: 10) {
                            horongStatusCard
                            emptyState
                        }
                    } else if scope == .week, weeklyDailyTotals.allSatisfy({ $0.durationSeconds == 0 }) {
                        emptyState
                    } else {
                        if scope == .today {
                            todaySummary
                        } else {
                            weekSummary
                        }
                    }
                }
                .padding(.trailing, 12)
            }
        }
        .onAppear { loadData() }
        .onChange(of: scope) { _, _ in loadData() }
        .configureHostWindow { window in
            hostWindow = window
        }
    }

    private var scopePicker: some View {
        HStack(spacing: 0) {
            ForEach(StatsSummaryScope.allCases) { item in
                Button {
                    scope = item
                } label: {
                    Text(item.rawValue)
                        .font(.system(size: 13, weight: scope == item ? .bold : .medium, design: .rounded))
                        .foregroundStyle(scope == item ? PopoverChrome.selectionInk : PopoverChrome.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous)
                                .fill(scopeChipFill(for: item))
                        )
                        .shadow(
                            color: PopoverChrome.isGamePixel ? .clear : (scope == item ? PopoverChrome.accent.opacity(0.28) : .clear),
                            radius: PopoverChrome.isGamePixel ? 0 : 8,
                            x: 0,
                            y: PopoverChrome.isGamePixel ? 0 : 4
                        )
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .onHover { isHovering in
                    hoveredScope = isHovering ? item : nil
                }
            }
        }
        .padding(4)
        .background(PopoverChrome.surfaceAlt.opacity(0.82), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(13), style: .continuous))
    }

    private func scopeChipFill(for item: StatsSummaryScope) -> Color {
        if scope == item {
            return PopoverChrome.selectionFill
        }
        if hoveredScope == item {
            return PopoverChrome.card
        }
        return .clear
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar")
                .font(.largeTitle)
                .foregroundStyle(PopoverChrome.inkTertiary)
            Text("아직 기록된 데이터가 없습니다")
                .font(.subheadline)
                .foregroundStyle(PopoverChrome.inkSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .popoverCard()
    }

    private var todaySummary: some View {
        VStack(spacing: appearanceDensity.popoverMetric(10)) {
            summaryHeader(title: "오늘 기록", total: "총 \(shortDuration(totalUsageSeconds))", showsTop3: true)

            if !categoryUsages.isEmpty {
                HStack(alignment: .center, spacing: 14) {
                    summaryDonut
                        .frame(width: 88, height: 88)
                    VStack(spacing: appearanceDensity.popoverMetric(6)) {
                        ForEach(topCategoryUsages) { usage in
                            compactUsageRow(usage)
                        }
                    }
                }
                .popoverCard()
            }

            if hasTodaySegmentDetails {
                metricCards
            }
            horongStatusCard
        }
    }

    private func summaryHeader(title: String, total: String, showsTop3: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(PopoverChrome.accent)
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                if showsTop3 {
                    Text("TOP 3")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                }
            }
            Spacer()
            detailButton
        }
        .overlay(alignment: .bottomLeading) {
            Text(total)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(PopoverChrome.inkSecondary)
                .offset(y: 20)
        }
        .padding(.bottom, 22)
    }

    private var summaryDonut: some View {
        let total = max(1, topCategoryUsages.reduce(0) { $0 + $1.durationSeconds })
        return ZStack {
            Circle()
                .stroke(PopoverChrome.surfaceAlt, lineWidth: 14)
            ForEach(Array(topCategoryUsages.enumerated()), id: \.element.id) { index, usage in
                Circle()
                    .trim(from: trimStart(for: index, total: total), to: trimEnd(for: index, total: total))
                    .stroke(usage.color, style: StrokeStyle(lineWidth: 14, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 0) {
                Text(shortDuration(total))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(PopoverChrome.ink)
            }
        }
    }

    private func trimStart(for index: Int, total: Int) -> CGFloat {
        let prior = topCategoryUsages.prefix(index).reduce(0) { $0 + $1.durationSeconds }
        return CGFloat(prior) / CGFloat(total)
    }

    private func trimEnd(for index: Int, total: Int) -> CGFloat {
        let through = topCategoryUsages.prefix(index + 1).reduce(0) { $0 + $1.durationSeconds }
        return CGFloat(through) / CGFloat(total)
    }

    private func compactUsageRow(_ usage: CategoryUsage) -> some View {
        let total = max(1, totalUsageSeconds)
        let percent = Int(round(Double(usage.durationSeconds) / Double(total) * 100))
        return HStack(spacing: appearanceDensity.popoverMetric(6)) {
            Circle()
                .fill(usage.color)
                .frame(width: 8, height: 8)
            Text(usage.emoji)
            Text(usage.category)
                .font(.system(size: appearanceDensity.popoverMetric(12)))
                .foregroundStyle(PopoverChrome.ink)
                .lineLimit(1)
            Spacer()
            Text(shortDuration(usage.durationSeconds))
                .font(.system(size: appearanceDensity.popoverMetric(12), weight: .bold))
                .monospacedDigit()
                .foregroundStyle(PopoverChrome.ink)
            Text("\(percent)%")
                .font(.system(size: appearanceDensity.popoverMetric(10)))
                .monospacedDigit()
                .foregroundStyle(PopoverChrome.inkTertiary)
                .frame(width: 30, alignment: .trailing)
        }
    }

    private var metricCards: some View {
        HStack(spacing: 8) {
            summaryMetricCard(label: "같은 카테고리 최장", value: shortDuration(todayFocusSummary.longestFocusSeconds))
            summaryMetricCard(label: "카테고리 전환", value: "\(todayFocusSummary.switches)회")
        }
    }

    private func summaryMetricCard(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: appearanceDensity.popoverMetric(4)) {
            Text(label)
                .font(.system(size: appearanceDensity.popoverMetric(11), weight: .medium, design: .rounded))
                .foregroundStyle(PopoverChrome.inkTertiary)
            Text(value)
                .font(.system(size: appearanceDensity.popoverMetric(17), weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(PopoverChrome.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .popoverCard(padding: appearanceDensity.popoverMetric(12), radius: 10)
    }

    private var horongStatusCard: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(PopoverChrome.focusOnImageName)
                .resizable()
                .interpolation(PopoverChrome.isGamePixel ? .none : .high)
                .scaledToFit()
                .padding(3)
                .frame(width: 30, height: 30)
                .background(PopoverChrome.card, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(focusNudge?.badge ?? "오늘의 관찰")
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverChrome.accent)
                    if focusNudge == nil {
                        Text("— 패턴을 알아가는 중")
                            .font(.system(size: 12.5, weight: .medium, design: .rounded))
                            .foregroundStyle(PopoverChrome.inkSecondary)
                    }
                }
                Text(focusNudge?.message ?? horongStatusMessage)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)

            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(PopoverChrome.surfaceAlt.opacity(0.84), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(12), style: .continuous))
    }

    private var usageBars: some View {
        VStack(spacing: 6) {
            ForEach(categoryUsages) { usage in
                HStack(spacing: 8) {
                    Text(usage.emoji)
                        .frame(width: 20)
                    Text(usage.category)
                        .font(.caption)
                        .foregroundStyle(PopoverChrome.ink)
                        .frame(width: 80, alignment: .leading)

                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(usage.color.opacity(0.78))
                            .frame(width: barWidth(for: usage, in: geo.size.width))
                    }
                    .frame(height: 12)

                    Text(usage.formattedDuration)
                        .font(.caption2)
                        .foregroundStyle(PopoverChrome.inkSecondary)
                        .frame(width: 50, alignment: .trailing)
                }
            }
        }
        .popoverCard()
    }

    private var weekSummary: some View {
        VStack(spacing: appearanceDensity.popoverMetric(10)) {
            summaryHeader(title: "이번 주 기록", total: "총 \(weekTotalFormatted)", showsTop3: false)

            VStack(spacing: 8) {
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(weeklyDailyTotals, id: \.date) { day in
                        weekBar(day)
                    }
                }
                .frame(height: 118, alignment: .bottom)
            }
            .overlay(alignment: .topTrailing) {
                Text(weekChartMaxLabel)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(PopoverChrome.inkTertiary)
                    .padding(.top, 2)
                    .padding(.trailing, 2)
            }
            .popoverCard()

            weekMetricCards
            weekStatusCard
        }
    }

    private func weekBar(_ day: StatsDayDuration) -> some View {
        let maxDuration = max(weekChartMaxDuration, 1)
        let height = day.durationSeconds > 0 ? max(8, CGFloat(day.durationSeconds) / CGFloat(maxDuration) * 78) : 8
        let calendar = Calendar.current
        let isToday = calendar.isDate(day.date, inSameDayAs: referenceDate)
        let isFuture = day.date > calendar.startOfDay(for: referenceDate)
        return VStack(spacing: 6) {
            ZStack(alignment: .bottom) {
                if isToday {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(PopoverChrome.accentSoft, lineWidth: 2)
                        .frame(width: 40, height: height + 8)
                }

                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(weekBarFill(duration: day.durationSeconds, isToday: isToday, isFuture: isFuture))
                    .frame(width: 32, height: height)
                    .padding(.bottom, isToday ? 4 : 0)
            }
            .frame(height: 94, alignment: .bottom)

            Text(weekdayLabel(day.date))
                .font(.caption2.weight(isToday ? .bold : .regular))
                .foregroundStyle(isToday ? PopoverChrome.accent : PopoverChrome.inkTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var weekChartMaxDuration: Int {
        weeklyDailyTotals.map(\.durationSeconds).max() ?? 0
    }

    private var weekChartMaxLabel: String {
        shortDuration(weekChartMaxDuration)
    }

    private func weekBarFill(duration: Int, isToday: Bool, isFuture: Bool) -> Color {
        if duration == 0 || isFuture {
            return PopoverChrome.surfaceAlt
        }
        return isToday ? PopoverChrome.accent : PopoverChrome.accent.opacity(0.9)
    }

    private var weekMetricCards: some View {
        HStack(spacing: 8) {
            summaryMetricCard(label: "오늘 누적", value: formatMetricDuration(todayWeeklySeconds))
            summaryMetricCard(label: "최장 세션", value: formatMetricDuration(weekLongestSessionSeconds))
        }
    }

    private var weekStatusCard: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(PopoverChrome.focusOnImageName)
                .resizable()
                .interpolation(PopoverChrome.isGamePixel ? .none : .high)
                .scaledToFit()
                .padding(3)
                .frame(width: 30, height: 30)
                .background(PopoverChrome.card, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text("\(weeklyActiveStreak)일 연속")
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverChrome.accent)
                    Text("호롱불을 켰어요 🔥")
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundStyle(PopoverChrome.inkSecondary)
                }
                Text("오늘도 작은 호롱이가 함께 있을게요.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(PopoverChrome.surfaceAlt.opacity(0.84), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(12), style: .continuous))
    }

    private var detailButton: some View {
        Button {
            HubWindowPresenter.present(
                tab: .stats,
                appState: appState,
                popoverWindow: hostWindow,
                openWindow: openWindow
            )
        } label: {
            HStack(spacing: 3) {
                Text("상세 보기")
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(PopoverChrome.inkSecondary)
        }
        .buttonStyle(.plain)
        .companionHighlight("stats.detail")
        .onReceive(
            NotificationCenter.default.publisher(for: .companionOnboardingPerform)
        ) { notification in
            guard notification.object as? String == "stats.openDetail" else { return }
            appState.hubTab = .stats
            openWindow(id: HubWindowPresenter.windowID)
        }
    }

    private var categoryUsages: [CategoryUsage] {
        viewModel.categoryDurations.map {
            CategoryUsage(
                category: $0.category,
                emoji: Constants.categoryEmoji(for: $0.category),
                color: Constants.categoryColor(for: $0.category),
                durationSeconds: $0.durationSeconds
            )
        }
    }

    private var weeklyDailyTotals: [StatsDayDuration] { viewModel.dailyDurations }
    private var todayFocusSummary: DailyFocusSummary { viewModel.todayFocusSummary }
    private var hasTodaySegmentDetails: Bool { viewModel.hasTodaySegmentDetails }
    private var focusNudge: StatsSummaryNudge? { viewModel.nudge }
    private var weekLongestSessionSeconds: Int { viewModel.weekLongestSessionSeconds }

    private var topCategoryUsages: [CategoryUsage] {
        Array(categoryUsages.prefix(3))
    }

    private var totalUsageSeconds: Int {
        categoryUsages.reduce(0) { $0 + $1.durationSeconds }
    }

    private var todayWeeklySeconds: Int {
        let calendar = Calendar.current
        return weeklyDailyTotals.first { calendar.isDate($0.date, inSameDayAs: referenceDate) }?.durationSeconds ?? 0
    }

    private var weeklyActiveStreak: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: referenceDate)
        let totalsByDay = Dictionary(uniqueKeysWithValues: weeklyDailyTotals.map {
            (calendar.startOfDay(for: $0.date), $0.durationSeconds)
        })

        var streak = 0
        var cursor = today
        while let duration = totalsByDay[cursor], duration > 0 {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    private var horongStatusMessage: String {
        guard todayFocusSummary.totalSeconds > 0 else {
            return "아직 기록이 없어요. 첫 기록을 시작해보세요."
        }

        guard hasTodaySegmentDetails else {
            return "\(formatMetricDuration(todayFocusSummary.totalSeconds)) 기록 · 카테고리별 집계만 있어 전환과 연속 시간은 알 수 없어요."
        }

        return "\(formatMetricDuration(todayFocusSummary.totalSeconds)) 기록 · 카테고리 전환 \(todayFocusSummary.switches)회 · 같은 카테고리 최장 \(formatMetricDuration(todayFocusSummary.longestFocusSeconds))"
    }

    private var totalFormatted: String {
        let total = categoryUsages.reduce(0) { $0 + $1.durationSeconds }
        let h = total / 3600
        let m = (total % 3600) / 60
        return "\(h)시간 \(m)분"
    }

    private var weekTotalFormatted: String {
        formatKoreanDuration(weeklyDailyTotals.reduce(0) { $0 + $1.durationSeconds })
    }

    private func barWidth(for usage: CategoryUsage, in maxWidth: CGFloat) -> CGFloat {
        let maxDuration = categoryUsages.map(\.durationSeconds).max() ?? 1
        guard maxDuration > 0 else { return 0 }
        return maxWidth * CGFloat(usage.durationSeconds) / CGFloat(maxDuration)
    }

    private func loadData() {
        switch scope {
        case .today:
            viewModel.loadToday(referenceDate: referenceDate)
        case .week:
            viewModel.loadWeek(referenceDate: referenceDate)
        }
    }

    private func shortDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        return "\(m)m"
    }

    private func formatKoreanDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        return "\(h)시간 \(m)분"
    }

    private func formatMetricDuration(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(max(0, seconds))초"
        }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 {
            return String(format: "%d시간 %02d분", h, m)
        }
        return "\(m)분"
    }

    private func weekdayLabel(_ date: Date) -> String {
        Self.weekdayFormatter.string(from: date)
    }
}
