import SwiftUI
import Charts
import SwiftData
import OSLog

// MARK: - Data models

struct ChartCategoryData: Identifiable {
    var id: String { category }
    let category: String
    let hours: Double
    let color: Color
}

struct DailyChartData: Identifiable {
    var id: String { "\(Int(date.timeIntervalSince1970))-\(category)" }
    let date: Date
    let category: String
    let hours: Double
}

struct CategoryAppsBreakdown: Identifiable {
    var id: String { category }
    let category: String
    let totalSeconds: Int
    let apps: [AppUsageEntry]
}

struct AppUsageEntry: Identifiable {
    var id: String { appName }
    let appName: String
    let durationSeconds: Int
}

struct PomodoroAppUsageEntry: Identifiable {
    var id: String { "\(appName)-\(category)" }
    let appName: String
    let category: String
    let durationSeconds: Int
}

struct PomodoroSessionBreakdown: Identifiable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let category: String
    let durationSeconds: Int
    let apps: [PomodoroAppUsageEntry]
}

struct PomodoroTimeSummary: Identifiable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let category: String
    let durationSeconds: Int
}

struct PomodoroCategorySummary: Identifiable {
    var id: String { category }
    let category: String
    let durationSeconds: Int
}

struct PomodoroDaySummary: Identifiable {
    var id: Int { Int(date.timeIntervalSince1970) }
    let date: Date
    let durationSeconds: Int
    let count: Int
}

private struct PomodoroFocusWindow {
    let start: Date
    let end: Date
    let category: String
}

private struct AttributedUsageSlice {
    let appName: String
    let category: String
    let durationSeconds: Int
}

enum StatsViewMode: String, CaseIterable, Identifiable {
    case daily = "일간"
    case weekly = "주간"
    case monthly = "월간"
    var id: String { rawValue }
}

// MARK: - Main view

struct StatsChartView: View {
    let records: [AppUsageRecord]
    let viewMode: StatsViewMode
    let referenceDate: Date
    /// 선택한 날짜의 세그먼트 (일간 뷰 타임라인용). 다른 뷰모드에서는 비어 있음.
    var dailySegments: [AppUsageSegment] = []
    /// 주간 뷰에서 해당 주 7일 세그먼트. 다른 뷰모드에서는 비어 있음.
    var weekSegments: [AppUsageSegment] = []
    /// 현재 선택 기간 전체 세그먼트. 통계 집계의 우선 원천으로 사용한다.
    var periodSegments: [AppUsageSegment] = []
    /// 현재 기간과 겹치는 타이머 세션. 전환 카운트 예외 판단에 쓰인다.
    var timerSessions: [FocusSession] = []
    /// 주간/월간 탭에서 원본 세그먼트 재집계를 피하기 위해 부모가 넘겨주는 집계 캐시.
    var aggregateSnapshot: StatsAggregateSnapshot? = nil

    @State private var weeklySelection: Date? = nil
    @State private var dailyAngleSelection: Double? = nil
    /// 부모(StatsDetailWindow)가 미리 계산해서 넘겨주는 휴가 일자 집합. 차트가 직접 store 를 관찰하지 않도록 함.
    var vacationDays: Set<Date> = []

    @AppStorage(Constants.AppStorageKey.timelineStartHour)
    private var timelineStartHour: Int = Constants.defaultTimelineStartHour
    @AppStorage(Constants.AppStorageKey.timelineEndHour)
    private var timelineEndHour: Int = Constants.defaultTimelineEndHour
    @AppStorage(Constants.AppStorageKey.timelineBucketMinutes)
    private var timelineBucketMinutes: Int = Constants.defaultTimelineBucketMinutes

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "app.horonghorong",
        category: "StatsChart"
    )

    private var activeRecords: [AppUsageRecord] {
        records.filter { !Constants.hiddenLegacyCategories.contains($0.category) }
    }

    private var activeSegments: [AppUsageSegment] {
        periodSegments.filter { !Constants.hiddenLegacyCategories.contains($0.category) }
    }

    private var activeUsageRecords: [AppUsageRecord] {
        activeRecords.filter {
            !$0.bundleIdentifier.hasPrefix(Constants.focusSessionBundlePrefix)
        }
    }

    private var hasSegmentSource: Bool {
        !activeSegments.isEmpty
    }

    private var hasAggregateSource: Bool {
        guard viewMode != .daily, let aggregateSnapshot else { return false }
        return !aggregateSnapshot.isEmpty
    }

    private var dataSourceLabel: String {
        if hasAggregateSource { return "aggregate" }
        if hasSegmentSource { return "segments" }
        return "records"
    }

    var body: some View {
        Group {
            switch viewMode {
            case .daily: dailyView
            case .weekly: weeklyView
            case .monthly: monthlyView
            }
        }
    }

    // MARK: - Daily

    private var dailyView: some View {
        VStack(alignment: .leading, spacing: 18) {
            if categoryData.isEmpty, pomodoroSessions.isEmpty {
                noDataView
            } else {
                if !categoryData.isEmpty {
                    DailyFocusSummaryCard(summary: dailySummary)

                    HStack(alignment: .top, spacing: 20) {
                        VStack(alignment: .leading, spacing: 10) {
                            donutChart(data: categoryData)
                                .frame(width: 220)
                            categoryLegend(data: categoryData)
                                .frame(maxWidth: 260)
                        }
                        .frame(width: 280, alignment: .top)
                        .popoverCard(padding: 14)

                        DailyTimelineBucketsView(
                            buckets: displayBuckets,
                            bucketSeconds: displayBucketSeconds,
                            emptyTitle: timelineEmptyTitle,
                            emptyDetail: timelineEmptyDetail
                        )
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }

                    categoryBreakdownSection
                }

                pomodoroDetailSection
            }
        }
    }

    // MARK: - Daily timeline derived data

    private var dailyBuckets: [TimelineBucket] {
        TimelineAnalytics.buckets(
            for: referenceDate,
            segments: dailySegments,
            timerSessions: timerSessions
        )
    }

    private var dailySummary: DailyFocusSummary {
        let summary: DailyFocusSummary
        if dailySegments.isEmpty, !activeUsageRecords.isEmpty {
            summary = recordBackedDailySummary
        } else {
            summary = TimelineAnalytics.summary(
                for: referenceDate,
                segments: dailySegments,
                buckets: dailyBuckets,
                timerSessions: timerSessions
            )
        }

        return DailyFocusSummary(
            totalSeconds: summary.totalSeconds,
            switches: summary.switches,
            longestFocusSeconds: summary.longestFocusSeconds,
            topCategory: categoryData.first?.category ?? summary.topCategory,
            overallScore: summary.overallScore
        )
    }

    private var recordBackedDailySummary: DailyFocusSummary {
        var totals: [String: Int] = [:]
        for record in activeUsageRecords {
            totals[record.category, default: 0] += record.durationSeconds
        }
        let totalSec = totals.values.reduce(0, +)
        let topCat = totals.max { $0.value < $1.value }?.key
        return DailyFocusSummary(
            totalSeconds: totalSec,
            switches: 0,
            longestFocusSeconds: 0,
            topCategory: topCat,
            overallScore: 0
        )
    }

    /// 사용자 설정에 따른 타임라인 표시용 버킷. 빈 구간도 채워서 스크롤 영역 시각적 일관성 유지.
    private var displayBucketSeconds: TimeInterval {
        TimeInterval(max(5, timelineBucketMinutes) * 60)
    }

    private var displayBuckets: [TimelineBucket] {
        let bucketSec = displayBucketSeconds
        let startHour = min(max(0, timelineStartHour), 23)
        let endHourRaw = max(timelineEndHour, startHour + 1)
        let endHour = min(endHourRaw, 24)

        let analytics = TimelineAnalytics.buckets(
            for: referenceDate,
            segments: dailySegments,
            timerSessions: timerSessions,
            bucketSeconds: bucketSec
        )
        let byStart = Dictionary(uniqueKeysWithValues: analytics.map { ($0.startTime, $0) })

        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: referenceDate)
        let rangeStart = dayStart.addingTimeInterval(Double(startHour) * 3600)
        let rangeEnd = dayStart.addingTimeInterval(Double(endHour) * 3600)

        var result: [TimelineBucket] = []
        var t = rangeStart
        while t < rangeEnd {
            if let existing = byStart[t] {
                result.append(existing)
            } else {
                let end = min(t.addingTimeInterval(bucketSec), rangeEnd)
                result.append(TimelineBucket(
                    startTime: t,
                    endTime: end,
                    categoryDurations: [:],
                    switches: 0
                ))
            }
            t = t.addingTimeInterval(bucketSec)
        }
        return result
    }

    private var hasTimelineDataForDay: Bool {
        dailyBuckets.contains { $0.totalSeconds > 0 }
    }

    private var hasTimelineDataInDisplayRange: Bool {
        displayBuckets.contains { $0.totalSeconds > 0 }
    }

    private var timelineEmptyTitle: String {
        if hasTimelineDataForDay && !hasTimelineDataInDisplayRange {
            return "표시 범위 안의 타임라인 기록이 없어요"
        }
        return "시간대별 세그먼트 기록이 없어요"
    }

    private var timelineEmptyDetail: String {
        if hasTimelineDataForDay && !hasTimelineDataInDisplayRange {
            return "설정의 타임라인 표시 시간 범위를 넓히면 볼 수 있습니다"
        }
        return "총 앱 사용 시간과 별도로 저장되며, 앱 전환/종료 이후의 기록부터 표시됩니다"
    }

    private func donutChart(data: [ChartCategoryData]) -> some View {
        let total = data.reduce(0) { $0 + $1.hours }
        let selected = selectedCategory(for: data)
        return Chart(data) { item in
            SectorMark(
                angle: .value("시간", item.hours),
                innerRadius: .ratio(0.55),
                outerRadius: selected == item.category ? .ratio(1.0) : .ratio(0.92),
                angularInset: 2
            )
            .foregroundStyle(item.color)
            .cornerRadius(4)
            .opacity(selected == nil || selected == item.category ? 1.0 : 0.45)
            .annotation(position: .overlay) {
                if total > 0, item.hours / total > 0.04 {
                    Text(percentLabel(item.hours, total: total))
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 1)
                }
            }
        }
        .chartAngleSelection(value: $dailyAngleSelection)
        .frame(height: 240)
        .overlay {
            donutCenterLabel(data: data, total: total, selected: selected)
        }
    }

    private func donutCenterLabel(data: [ChartCategoryData], total: Double, selected: String?) -> some View {
        VStack(spacing: 2) {
            if let sel = selected, let item = data.first(where: { $0.category == sel }) {
            Text(Constants.categoryEmoji(for: sel))
                .font(.title3)
            Text(sel)
                .font(.callout.bold())
                .foregroundStyle(PopoverChrome.ink)
            Text(formatHours(item.hours))
                .font(.caption)
                .foregroundStyle(PopoverChrome.inkSecondary)
                .monospacedDigit()
            Text(percentLabel(item.hours, total: total))
                .font(.caption)
                .foregroundStyle(PopoverChrome.inkTertiary)
                .monospacedDigit()
        } else {
            Text("총 앱 사용 시간")
                .font(.caption)
                .foregroundStyle(PopoverChrome.inkTertiary)
            Text(formatHours(total))
                .font(.title3.bold())
                .foregroundStyle(PopoverChrome.ink)
                .monospacedDigit()
        }
        }
    }

    private func selectedCategory(for data: [ChartCategoryData]) -> String? {
        guard let target = dailyAngleSelection else { return nil }
        var cumulative: Double = 0
        for item in data {
            cumulative += item.hours
            if target <= cumulative { return item.category }
        }
        return data.last?.category
    }

    private func categoryLegend(data: [ChartCategoryData]) -> some View {
        let total = data.reduce(0) { $0 + $1.hours }
        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 140), spacing: 8)],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(data) { item in
                HStack(spacing: 6) {
                    Circle()
                        .fill(item.color)
                        .frame(width: 10, height: 10)
                    Text(Constants.categoryEmoji(for: item.category))
                    Text(item.category)
                        .font(.callout)
                        .foregroundStyle(PopoverChrome.ink)
                    Spacer(minLength: 4)
                    Text(formatHours(item.hours))
                        .font(.caption)
                        .foregroundStyle(PopoverChrome.inkSecondary)
                        .monospacedDigit()
                    Text(percentLabel(item.hours, total: total))
                        .font(.caption)
                        .foregroundStyle(PopoverChrome.inkTertiary)
                        .monospacedDigit()
                        .frame(width: 38, alignment: .trailing)
                }
            }
        }
    }

    private var categoryBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("카테고리별 앱 사용")
                .font(.headline)
                .foregroundStyle(PopoverChrome.ink)
            ForEach(categoryBreakdownData) { group in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Constants.categoryColor(for: group.category))
                            .frame(width: 10, height: 10)
                        Text(Constants.categoryEmoji(for: group.category))
                        Text(group.category)
                            .font(.callout.bold())
                            .foregroundStyle(PopoverChrome.ink)
                        Spacer()
                        Text(formatDuration(group.totalSeconds))
                            .font(.callout.bold())
                            .foregroundStyle(PopoverChrome.ink)
                            .monospacedDigit()
                    }
                    ForEach(group.apps) { app in
                        HStack {
                            Text(app.appName)
                                .font(.callout)
                                .foregroundStyle(PopoverChrome.inkSecondary)
                                .padding(.leading, 22)
                            Spacer()
                            Text(formatDuration(app.durationSeconds))
                                .font(.callout)
                                .foregroundStyle(PopoverChrome.inkSecondary)
                                .monospacedDigit()
                        }
                    }
                }
                .padding(.vertical, 4)
                Rectangle()
                    .fill(PopoverChrome.divider)
                    .frame(height: 1)
            }
        }
        .popoverCard(padding: 14)
    }

    // MARK: - Weekly

    private var weeklyView: some View {
        VStack(alignment: .leading, spacing: 16) {
            if weeklyStackedData.isEmpty, pomodoroTimeSummaries.isEmpty {
                noDataView
            } else {
                if !weeklyStackedData.isEmpty {
                    weeklyTooltipPanel
                    weeklyFocusLegend
                    weeklyStackedChart
                    categoryLegend(data: categoryData)
                    Divider()
                    weeklyCategoryTotals
                }

                weeklyPomodoroSection
            }
        }
    }

    private var weeklyFocusLegend: some View {
        HStack(spacing: 6) {
            Text("요일 아래 점은 그날의 집중도")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Text("🟢 집중 · 🟡 보통 · 🔴 산만")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var weeklySnappedDate: Date? {
        guard let sel = weeklySelection else { return nil }
        let cal = Calendar.current
        return weeklyDays.first { cal.isDate($0, inSameDayAs: sel) }
    }

    private var weeklyTooltipPanel: some View {
        Group {
            if let date = weeklySnappedDate {
                weeklyHoverTooltip(for: date)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "hand.point.up.left")
                    Text("막대에 커서를 올리면 해당 일자의 카테고리별 사용량이 표시됩니다")
                        .font(.caption)
                }
                .foregroundStyle(PopoverChrome.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .popoverCard(padding: 10)
            }
        }
        .frame(minHeight: 96, alignment: .topLeading)
    }

    private var weeklyStackedChart: some View {
        let focusByDay = weeklyFocusByDay
        return Chart {
            ForEach(weeklyStackedData) { item in
                BarMark(
                    x: .value("요일", item.date, unit: .day),
                    y: .value("시간", item.hours)
                )
                .foregroundStyle(Constants.categoryColor(for: item.category))
                .cornerRadius(2)
                .opacity(opacityForBar(item))
            }
            if let snapped = weeklySnappedDate {
                RuleMark(x: .value("선택", snapped, unit: .day))
                    .foregroundStyle(.gray.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartXScale(domain: weeklyDomain)
        .chartXAxis {
            AxisMarks(values: weeklyDays) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        let key = Calendar.current.startOfDay(for: date)
                        weekdayAxisLabel(date: date, level: focusByDay[key] ?? .empty)
                    }
                }
            }
        }
        .chartYAxisLabel("시간 (h)")
        .chartXSelection(value: $weeklySelection)
        .frame(height: 260)
        .padding(12)
        .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(PopoverChrome.border, lineWidth: 1)
        )
    }

    private func weekdayAxisLabel(date: Date, level: DailyFocusSummary.Level) -> some View {
        VStack(spacing: 3) {
            Text(weekdayShortLabel(date))
                .font(.caption2)
            Circle()
                .fill(focusDotColor(level))
                .frame(width: 7, height: 7)
        }
        .padding(.top, 2)
    }

    private func weekdayShortLabel(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "EEE"
        return fmt.string(from: date)
    }

    private func focusDotColor(_ level: DailyFocusSummary.Level) -> Color {
        switch level {
        case .focused: return .green
        case .moderate: return .yellow
        case .scattered: return .red
        case .empty: return Color.secondary.opacity(0.25)
        }
    }

    private var weeklyFocusByDay: [Date: DailyFocusSummary.Level] {
        let startedAt = Date()
        if hasAggregateSource, let aggregateSnapshot, !aggregateSnapshot.dailyFocusLevels.isEmpty {
            let result = Dictionary(uniqueKeysWithValues: aggregateSnapshot.dailyFocusLevels.map {
                ($0.day, focusLevel(from: $0.level))
            })
            logChartBuild("weeklyFocusByDay", rows: result.count, startedAt: startedAt, source: "aggregate")
            return result
        }

        let cal = Calendar.current
        var result: [Date: DailyFocusSummary.Level] = [:]
        for day in weeklyDays {
            guard let dayEnd = cal.date(byAdding: .day, value: 1, to: day) else { continue }
            let segs = weekSegments.filter {
                $0.startTime < dayEnd && $0.endTime > day
            }
            let bks = TimelineAnalytics.buckets(
                for: day,
                segments: segs,
                timerSessions: timerSessions
            )
            let sum = TimelineAnalytics.summary(
                for: day,
                segments: segs,
                buckets: bks,
                timerSessions: timerSessions
            )
            result[day] = sum.level
        }
        logChartBuild("weeklyFocusByDay", rows: result.count, startedAt: startedAt, source: "segments")
        return result
    }

    private func opacityForBar(_ item: DailyChartData) -> Double {
        guard let snapped = weeklySnappedDate else { return 1.0 }
        return Calendar.current.isDate(item.date, inSameDayAs: snapped) ? 1.0 : 0.45
    }

    private func weeklyHoverTooltip(for date: Date) -> some View {
        let cal = Calendar.current
        let items = weeklyStackedData
            .filter { cal.isDate($0.date, inSameDayAs: date) }
            .sorted { $0.hours > $1.hours }
        let total = items.reduce(0) { $0 + $1.hours }
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(dayLabel(date))
                    .font(.caption.bold())
                    .foregroundStyle(PopoverChrome.ink)
                Spacer()
                Text(formatHours(total))
                    .font(.caption.bold())
                    .foregroundStyle(PopoverChrome.ink)
                    .monospacedDigit()
            }
            if items.isEmpty {
                Text("기록 없음")
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkSecondary)
            } else {
                ForEach(items) { item in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Constants.categoryColor(for: item.category))
                            .frame(width: 8, height: 8)
                        Text(item.category).font(.caption)
                            .foregroundStyle(PopoverChrome.inkSecondary)
                        Spacer(minLength: 8)
                        Text(formatHours(item.hours))
                            .font(.caption)
                            .foregroundStyle(PopoverChrome.ink)
                            .monospacedDigit()
                    }
                }
            }
        }
        .popoverCard(padding: 10)
        .frame(minWidth: 160)
    }

    private var weeklyCategoryTotals: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("이번 주 카테고리 합계")
                .font(.headline)
                .foregroundStyle(PopoverChrome.ink)
            ForEach(categoryData) { item in
                HStack(spacing: 8) {
                    Circle()
                        .fill(item.color)
                        .frame(width: 10, height: 10)
                    Text(Constants.categoryEmoji(for: item.category))
                    Text(item.category).font(.callout)
                        .foregroundStyle(PopoverChrome.ink)
                    Spacer()
                    Text(formatHours(item.hours))
                        .font(.callout)
                        .foregroundStyle(PopoverChrome.ink)
                        .monospacedDigit()
                }
            }
        }
        .popoverCard(padding: 14)
    }

    // MARK: - Monthly

    private var monthlyView: some View {
        VStack(alignment: .leading, spacing: 24) {
            if categoryData.isEmpty, pomodoroTimeSummaries.isEmpty {
                noDataView
            } else {
                if !categoryData.isEmpty {
                    monthlyHeatmapSection
                    monthlyCategorySection
                    monthlyTopAppsSection
                }

                monthlyPomodoroSection
            }
        }
    }

    private var monthlyHeatmapSection: some View {
        let totals = monthlyDailyTotalsMap
        let total = totals.values.reduce(0, +)
        let active = totals.values.filter { $0 > 0 }.count
        let avg = active > 0 ? total / Double(active) : 0
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("일별 사용 시간")
                    .font(.headline)
                    .foregroundStyle(PopoverChrome.ink)
                Spacer()
                Text("총 \(formatHours(total)) · 사용한 날 \(active)일 · 일평균 \(formatHours(avg))")
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkSecondary)
            }
            HeatmapCalendar(
                dailyTotals: totals,
                month: referenceDate,
                vacationDates: vacationDays
            )
        }
        .popoverCard(padding: 14)
    }

    private var monthlyCategorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("카테고리 분포")
                .font(.headline)
                .foregroundStyle(PopoverChrome.ink)
            HStack(alignment: .top, spacing: 16) {
                donutChart(data: categoryData)
                    .frame(width: 220)
                categoryLegend(data: categoryData)
            }
        }
        .popoverCard(padding: 14)
    }

    private var monthlyTopAppsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top 10 앱")
                .font(.headline)
                .foregroundStyle(PopoverChrome.ink)
            ForEach(Array(appDetails.prefix(10).enumerated()), id: \.offset) { idx, app in
                HStack {
                    Text("\(idx + 1)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(PopoverChrome.inkTertiary)
                        .frame(width: 22, alignment: .trailing)
                    Text(Constants.categoryEmoji(for: app.category))
                    Text(app.appName).font(.callout)
                        .foregroundStyle(PopoverChrome.ink)
                    Spacer()
                    Text(app.category)
                        .font(.caption)
                        .foregroundStyle(PopoverChrome.inkSecondary)
                    Text(formatDuration(app.durationSeconds))
                        .font(.callout)
                        .foregroundStyle(PopoverChrome.ink)
                        .monospacedDigit()
                }
            }
        }
        .popoverCard(padding: 14)
    }

    // MARK: - Empty state

    private var noDataView: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("해당 기간에 기록된 데이터가 없습니다")
                .foregroundStyle(PopoverChrome.inkSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .popoverCard()
    }

    // MARK: - Pomodoro

    private var pomodoroDetailSection: some View {
        Group {
            if !pomodoroSessions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("포모도로 집중")
                            .font(.headline)
                            .foregroundStyle(PopoverChrome.ink)
                        Spacer()
                        Text("총 \(formatDuration(pomodoroTotalSeconds)) · \(pomodoroSessions.count)회")
                            .font(.caption)
                            .foregroundStyle(PopoverChrome.inkSecondary)
                    }

                    ForEach(pomodoroSessions) { session in
                        pomodoroSessionRow(session)
                    }
                }
                .popoverCard(padding: 14)
            }
        }
    }

    private var weeklyPomodoroSection: some View {
        Group {
            if !pomodoroTimeSummaries.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("포모도로 집중")
                            .font(.headline)
                            .foregroundStyle(PopoverChrome.ink)
                        Spacer()
                        Text("총 \(formatDuration(pomodoroSummaryTotalSeconds)) · \(pomodoroTimeSummaries.count)회")
                            .font(.caption)
                            .foregroundStyle(PopoverChrome.inkSecondary)
                    }

                    HStack(alignment: .top, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("카테고리별")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(PopoverChrome.inkSecondary)
                            ForEach(pomodoroCategoryData) { item in
                                pomodoroCategoryRow(item)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("요일별")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(PopoverChrome.inkSecondary)
                            ForEach(weeklyPomodoroDayData) { item in
                                pomodoroDayRow(item)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
                .popoverCard(padding: 14)
            }
        }
    }

    private var monthlyPomodoroSection: some View {
        Group {
            if !pomodoroTimeSummaries.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("포모도로 집중")
                            .font(.headline)
                            .foregroundStyle(PopoverChrome.ink)
                        Spacer()
                        Text("총 \(formatDuration(pomodoroSummaryTotalSeconds)) · \(pomodoroTimeSummaries.count)회")
                            .font(.caption)
                            .foregroundStyle(PopoverChrome.inkSecondary)
                    }

                    ForEach(pomodoroCategoryData) { item in
                        pomodoroCategoryRow(item)
                    }
                }
                .popoverCard(padding: 14)
            }
        }
    }

    private func pomodoroCategoryRow(_ item: PomodoroCategorySummary) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Constants.categoryColor(for: item.category))
                .frame(width: 10, height: 10)
            Text(Constants.categoryEmoji(for: item.category))
            Text(item.category)
                .font(.callout)
                .foregroundStyle(PopoverChrome.ink)
            Spacer()
            Text(formatDuration(item.durationSeconds))
                .font(.callout.weight(.semibold))
                .foregroundStyle(PopoverChrome.ink)
                .monospacedDigit()
        }
    }

    private func pomodoroDayRow(_ item: PomodoroDaySummary) -> some View {
        HStack(spacing: 8) {
            Text(weekdayShortLabel(item.date))
                .font(.caption.weight(.semibold))
                .foregroundStyle(PopoverChrome.inkSecondary)
                .frame(width: 24, alignment: .leading)
            Text(formatDuration(item.durationSeconds))
                .font(.callout.weight(.semibold))
                .foregroundStyle(PopoverChrome.ink)
                .monospacedDigit()
            Spacer()
            Text("\(item.count)회")
                .font(.caption)
                .foregroundStyle(PopoverChrome.inkSecondary)
        }
    }

    private func pomodoroSessionRow(_ session: PomodoroSessionBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(Constants.categoryEmoji(for: session.category))
                    Text(session.category)
                        .font(.callout.bold())
                        .foregroundStyle(PopoverChrome.ink)
                    Text(pomodoroTimeRange(session))
                        .font(.caption)
                        .foregroundStyle(PopoverChrome.inkSecondary)
                    Spacer()
                    Text(formatDuration(session.durationSeconds))
                        .font(.callout.bold())
                        .foregroundStyle(PopoverChrome.ink)
                        .monospacedDigit()
                }

                if session.apps.isEmpty {
                    Text("세션 중 앱 사용 기록 없음")
                        .font(.caption)
                        .foregroundStyle(PopoverChrome.inkSecondary)
                        .padding(.leading, 22)
                } else {
                    ForEach(session.apps) { app in
                        HStack(spacing: 6) {
                            Text(app.appName)
                                .font(.callout)
                                .foregroundStyle(PopoverChrome.inkSecondary)
                                .padding(.leading, 22)
                            Text(app.category)
                                .font(.caption)
                                .foregroundStyle(PopoverChrome.inkTertiary)
                            Spacer()
                            Text(formatDuration(app.durationSeconds))
                                .font(.callout)
                                .foregroundStyle(PopoverChrome.inkSecondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .padding(.vertical, 6)
            Divider()
        }
    }

    // MARK: - Derived data

    private var categoryData: [ChartCategoryData] {
        let startedAt = Date()
        let durations: [String: Int]
        if hasAggregateSource, let aggregateSnapshot {
            durations = aggregateSnapshot.categoryDurations
        } else {
            durations = hasSegmentSource ? segmentDurationsByCategory : recordDurationsByCategory
        }

        let result = durations
            .sorted {
                if $0.value != $1.value { return $0.value > $1.value }
                return $0.key < $1.key
            }
            .map { ChartCategoryData(
                category: $0.key,
                hours: Double($0.value) / 3600.0,
                color: Constants.categoryColor(for: $0.key)
            )}
        logChartBuild("categoryData", rows: result.count, startedAt: startedAt, source: dataSourceLabel)
        return result
    }

    private var appDetails: [(appName: String, category: String, durationSeconds: Int)] {
        let startedAt = Date()
        var details: [String: (appName: String, category: String, duration: Int)] = [:]
        if hasSegmentSource {
            for segment in activeSegments {
                for slice in attributedSlices(for: segment) {
                    let key = "\(slice.appName)\u{1F}\(slice.category)"
                    if let existing = details[key] {
                        details[key] = (existing.appName, existing.category, existing.duration + slice.durationSeconds)
                    } else {
                        details[key] = (slice.appName, slice.category, slice.durationSeconds)
                    }
                }
            }
        } else {
            addRecordDetails(activeUsageRecords, to: &details)
        }
        let result = details
            .sorted { $0.value.duration > $1.value.duration }
            .map { (appName: $0.value.appName, category: $0.value.category, durationSeconds: $0.value.duration) }
        logChartBuild("appDetails", rows: result.count, startedAt: startedAt, source: dataSourceLabel)
        return result
    }

    private var categoryBreakdownData: [CategoryAppsBreakdown] {
        let startedAt = Date()
        var groups: [String: [String: Int]] = [:]
        if hasSegmentSource {
            for segment in activeSegments {
                for slice in attributedSlices(for: segment) {
                    groups[slice.category, default: [:]][slice.appName, default: 0] += slice.durationSeconds
                }
            }
        } else {
            addRecordBreakdown(activeUsageRecords, to: &groups)
        }
        let result = groups
            .map { (cat, apps) in
                let total = apps.values.reduce(0, +)
                let appList = apps
                    .sorted { $0.value > $1.value }
                    .map { AppUsageEntry(appName: $0.key, durationSeconds: $0.value) }
                return CategoryAppsBreakdown(category: cat, totalSeconds: total, apps: appList)
            }
            .sorted { $0.totalSeconds > $1.totalSeconds }
        logChartBuild("categoryBreakdownData", rows: result.count, startedAt: startedAt, source: dataSourceLabel)
        return result
    }

    private var recordDurationsByCategory: [String: Int] {
        var durations: [String: Int] = [:]
        for record in activeUsageRecords {
            durations[record.category, default: 0] += record.durationSeconds
        }
        return durations
    }

    private var segmentDurationsByCategory: [String: Int] {
        var durations: [String: Int] = [:]
        for segment in activeSegments {
            for slice in attributedSlices(for: segment) {
                durations[slice.category, default: 0] += slice.durationSeconds
            }
        }
        return durations
    }

    private var periodBounds: (start: Date, end: Date)? {
        let calendar = Calendar.current
        switch viewMode {
        case .daily:
            let start = calendar.startOfDay(for: referenceDate)
            return (start, calendar.date(byAdding: .day, value: 1, to: start) ?? start)
        case .weekly:
            guard let start = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: referenceDate)),
                  let end = calendar.date(byAdding: .day, value: 7, to: start) else {
                return nil
            }
            return (start, end)
        case .monthly:
            guard let start = calendar.date(from: calendar.dateComponents([.year, .month], from: referenceDate)),
                  let end = calendar.date(byAdding: .month, value: 1, to: start) else {
                return nil
            }
            return (start, end)
        }
    }

    private func clippedDuration(_ segment: AppUsageSegment) -> Int {
        guard let bounds = periodBounds else { return 0 }
        let start = max(segment.startTime, bounds.start)
        let end = min(segment.endTime, bounds.end)
        guard end > start else { return 0 }
        return Int(end.timeIntervalSince(start))
    }

    private func clippedDuration(_ segment: AppUsageSegment, in day: Date) -> Int {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return 0 }
        let start = max(segment.startTime, dayStart)
        let end = min(segment.endTime, dayEnd)
        guard end > start else { return 0 }
        return Int(end.timeIntervalSince(start))
    }

    private func attributedSlices(for segment: AppUsageSegment) -> [AttributedUsageSlice] {
        guard let bounds = periodBounds else { return [] }
        return attributedSlices(for: segment, from: bounds.start, to: bounds.end)
    }

    private func attributedSlices(for segment: AppUsageSegment, in day: Date) -> [AttributedUsageSlice] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        return attributedSlices(for: segment, from: dayStart, to: dayEnd)
    }

    private func attributedSlices(for segment: AppUsageSegment, from start: Date, to end: Date) -> [AttributedUsageSlice] {
        let segmentStart = max(segment.startTime, start)
        let segmentEnd = min(segment.endTime, end)
        guard segmentEnd > segmentStart else { return [] }

        var remaining: [(start: Date, end: Date)] = [(segmentStart, segmentEnd)]
        var slices: [AttributedUsageSlice] = []

        for window in pomodoroFocusWindows(from: segmentStart, to: segmentEnd) {
            let overlapStart = max(segmentStart, window.start)
            let overlapEnd = min(segmentEnd, window.end)
            guard overlapEnd > overlapStart else { continue }

            let duration = Int(overlapEnd.timeIntervalSince(overlapStart))
            if duration > 0 {
                slices.append(AttributedUsageSlice(
                    appName: segment.appName,
                    category: window.category,
                    durationSeconds: duration
                ))
            }

            remaining = remaining.flatMap { interval -> [(start: Date, end: Date)] in
                let clippedStart = max(interval.start, overlapStart)
                let clippedEnd = min(interval.end, overlapEnd)
                guard clippedEnd > clippedStart else { return [interval] }

                var parts: [(start: Date, end: Date)] = []
                if interval.start < clippedStart {
                    parts.append((interval.start, clippedStart))
                }
                if clippedEnd < interval.end {
                    parts.append((clippedEnd, interval.end))
                }
                return parts
            }
        }

        for interval in remaining {
            let duration = Int(interval.end.timeIntervalSince(interval.start))
            guard duration > 0 else { continue }
            slices.append(AttributedUsageSlice(
                appName: segment.appName,
                category: segment.category,
                durationSeconds: duration
            ))
        }

        return slices
    }

    private func pomodoroFocusWindows(from start: Date, to end: Date) -> [PomodoroFocusWindow] {
        var windows: [PomodoroFocusWindow] = []
        for session in timerSessions {
            guard let focusEnd = focusEnd(for: session) else { continue }
            if focusEnd <= start { continue }
            if session.startedAt >= end { break }
            guard isCompletedPomodoro(session) else { continue }

            let windowStart = max(session.startedAt, start)
            let windowEnd = min(focusEnd, end)
            guard windowEnd > windowStart else { continue }

            windows.append(PomodoroFocusWindow(
                start: windowStart,
                end: windowEnd,
                category: session.category ?? Constants.defaultFocusCategory
            ))
        }
        return windows
    }

    private var dailySegmentCategoryData: [DailyChartData] {
        var grouped: [Date: [String: Int]] = [:]
        for day in weeklyDays {
            for segment in activeSegments {
                for slice in attributedSlices(for: segment, in: day) {
                    grouped[day, default: [:]][slice.category, default: 0] += slice.durationSeconds
                }
            }
        }
        var result: [DailyChartData] = []
        for (date, categories) in grouped {
            for (category, seconds) in categories {
                result.append(DailyChartData(
                    date: date,
                    category: category,
                    hours: Double(seconds) / 3600.0
                ))
            }
        }
        return result.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.category < $1.category
        }
    }

    private var dailyRecordCategoryData: [DailyChartData] {
        var grouped: [Date: [String: Int]] = [:]
        for record in activeUsageRecords {
            let day = Calendar.current.startOfDay(for: record.date)
            grouped[day, default: [:]][record.category, default: 0] += record.durationSeconds
        }
        var result: [DailyChartData] = []
        for (date, categories) in grouped {
            for (category, seconds) in categories {
                result.append(DailyChartData(
                    date: date,
                    category: category,
                    hours: Double(seconds) / 3600.0
                ))
            }
        }
        return result.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.category < $1.category
        }
    }

    private var dailySegmentTotalsMap: [Date: Double] {
        // 세그먼트 1개씩 한 번만 훑으며 자정을 넘는 구간만 분할한다.
        // 기존 O(days × segments) 중첩 루프 대비 월간 뷰에서 수만 배 이상 빠르다.
        guard let bounds = periodBounds else { return [:] }
        var totals: [Date: Int] = [:]
        let calendar = Calendar.current
        for segment in activeSegments {
            var cursor = max(segment.startTime, bounds.start)
            let segmentEnd = min(segment.endTime, bounds.end)
            while cursor < segmentEnd {
                let day = calendar.startOfDay(for: cursor)
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                let chunkEnd = min(segmentEnd, nextDay)
                let seconds = Int(chunkEnd.timeIntervalSince(cursor))
                if seconds > 0 {
                    totals[day, default: 0] += seconds
                }
                cursor = chunkEnd
            }
        }
        return totals.mapValues { Double($0) / 3600.0 }
    }

    private var dailyRecordTotalsMap: [Date: Double] {
        var totals: [Date: Int] = [:]
        for record in activeUsageRecords {
            let day = Calendar.current.startOfDay(for: record.date)
            totals[day, default: 0] += record.durationSeconds
        }
        return totals.mapValues { Double($0) / 3600.0 }
    }

    private var weeklyStackedData: [DailyChartData] {
        let startedAt = Date()
        if hasAggregateSource, let aggregateSnapshot {
            let result = aggregateSnapshot.dailyCategories.map {
                DailyChartData(
                    date: $0.day,
                    category: $0.category,
                    hours: Double($0.durationSeconds) / 3600.0
                )
            }
            logChartBuild("weeklyStackedData", rows: result.count, startedAt: startedAt, source: "aggregate")
            return result
        }
        let result = hasSegmentSource ? dailySegmentCategoryData : dailyRecordCategoryData
        logChartBuild("weeklyStackedData", rows: result.count, startedAt: startedAt, source: dataSourceLabel)
        return result
    }

    private var monthlyDailyTotalsMap: [Date: Double] {
        let startedAt = Date()
        if hasAggregateSource, let aggregateSnapshot {
            let result = aggregateSnapshot.dailyDurations.mapValues { Double($0) / 3600.0 }
            logChartBuild("monthlyDailyTotalsMap", rows: result.count, startedAt: startedAt, source: "aggregate")
            return result
        }
        let result = hasSegmentSource ? dailySegmentTotalsMap : dailyRecordTotalsMap
        logChartBuild("monthlyDailyTotalsMap", rows: result.count, startedAt: startedAt, source: dataSourceLabel)
        return result
    }

    private func focusLevel(from value: String) -> DailyFocusSummary.Level {
        switch value {
        case "focused":
            return .focused
        case "moderate":
            return .moderate
        case "scattered":
            return .scattered
        default:
            return .empty
        }
    }

    private func addRecordDetails(
        _ records: [AppUsageRecord],
        to details: inout [String: (appName: String, category: String, duration: Int)]
    ) {
        for record in records {
            let key = "\(record.appName)\u{1F}\(record.category)"
            if let existing = details[key] {
                details[key] = (existing.appName, existing.category, existing.duration + record.durationSeconds)
            } else {
                details[key] = (record.appName, record.category, record.durationSeconds)
            }
        }
    }

    private func addRecordBreakdown(
        _ records: [AppUsageRecord],
        to groups: inout [String: [String: Int]]
    ) {
        for record in records {
            groups[record.category, default: [:]][record.appName, default: 0] += record.durationSeconds
        }
    }

    private var pomodoroSessions: [PomodoroSessionBreakdown] {
        return pomodoroTimeSummaries.map { summary in
            return PomodoroSessionBreakdown(
                id: summary.id,
                startedAt: summary.startedAt,
                endedAt: summary.endedAt,
                category: summary.category,
                durationSeconds: summary.durationSeconds,
                apps: pomodoroApps(from: summary.startedAt, to: summary.endedAt)
            )
        }
    }

    private var pomodoroTotalSeconds: Int {
        pomodoroSessions.reduce(0) { $0 + $1.durationSeconds }
    }

    private var pomodoroTimeSummaries: [PomodoroTimeSummary] {
        let startedAt = Date()
        guard let bounds = periodBounds else { return [] }
        let result: [PomodoroTimeSummary] = timerSessions.compactMap { session in
            guard isCompletedPomodoro(session),
                  let focusEnd = focusEnd(for: session) else {
                return nil
            }
            let start = max(session.startedAt, bounds.start)
            let end = min(focusEnd, bounds.end)
            guard end > start else { return nil }

            return PomodoroTimeSummary(
                id: session.id,
                startedAt: start,
                endedAt: end,
                category: session.category ?? Constants.defaultFocusCategory,
                durationSeconds: Int(end.timeIntervalSince(start))
            )
        }
        .sorted { $0.startedAt < $1.startedAt }
        logChartBuild("pomodoroTimeSummaries", rows: result.count, startedAt: startedAt, source: "sessions")
        return result
    }

    private var pomodoroSummaryTotalSeconds: Int {
        pomodoroTimeSummaries.reduce(0) { $0 + $1.durationSeconds }
    }

    private var pomodoroCategoryData: [PomodoroCategorySummary] {
        var durations: [String: Int] = [:]
        for session in pomodoroTimeSummaries {
            durations[session.category, default: 0] += session.durationSeconds
        }
        return durations
            .sorted {
                if $0.value != $1.value { return $0.value > $1.value }
                return $0.key < $1.key
            }
            .map { PomodoroCategorySummary(category: $0.key, durationSeconds: $0.value) }
    }

    private var weeklyPomodoroDayData: [PomodoroDaySummary] {
        let cal = Calendar.current
        var durations: [Date: Int] = [:]
        var counts: [Date: Int] = [:]
        for session in pomodoroTimeSummaries {
            let day = cal.startOfDay(for: session.startedAt)
            durations[day, default: 0] += session.durationSeconds
            counts[day, default: 0] += 1
        }
        return weeklyDays.map { day in
            PomodoroDaySummary(
                date: day,
                durationSeconds: durations[day] ?? 0,
                count: counts[day] ?? 0
            )
        }
    }

    private func logChartBuild(_ name: String, rows: Int, startedAt: Date, source: String) {
        let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1_000)
        Self.logger.notice("StatsChart data build mode=\(viewMode.rawValue, privacy: .public) name=\(name, privacy: .public) source=\(source, privacy: .public) rows=\(rows) elapsed=\(elapsedMs)ms")
    }

    private func isCompletedPomodoro(_ session: FocusSession) -> Bool {
        guard let endedAt = session.endedAt else { return false }
        let expectedSeconds = max(0, session.focusMinutes) * 60
        guard expectedSeconds > 0 else { return false }
        return session.completed || endedAt.timeIntervalSince(session.startedAt) >= TimeInterval(expectedSeconds)
    }

    private func focusEnd(for session: FocusSession) -> Date? {
        guard let endedAt = session.endedAt else { return nil }
        let expectedEnd = session.startedAt.addingTimeInterval(TimeInterval(max(0, session.focusMinutes) * 60))
        return min(endedAt, expectedEnd)
    }

    private func pomodoroApps(from start: Date, to end: Date) -> [PomodoroAppUsageEntry] {
        var apps: [String: (appName: String, category: String, duration: Int)] = [:]
        for segment in activeSegments {
            if segment.endTime <= start { continue }
            if segment.startTime >= end { break }

            let clippedStart = max(segment.startTime, start)
            let clippedEnd = min(segment.endTime, end)
            guard clippedEnd > clippedStart else { continue }

            let key = "\(segment.appName)\u{1F}\(segment.category)"
            let duration = Int(clippedEnd.timeIntervalSince(clippedStart))
            if let existing = apps[key] {
                apps[key] = (existing.appName, existing.category, existing.duration + duration)
            } else {
                apps[key] = (segment.appName, segment.category, duration)
            }
        }

        return apps.values
            .sorted { $0.duration > $1.duration }
            .map {
                PomodoroAppUsageEntry(
                    appName: $0.appName,
                    category: $0.category,
                    durationSeconds: $0.duration
                )
            }
    }

    private var weeklyDays: [Date] {
        let cal = Calendar.current
        guard let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: referenceDate)) else {
            return []
        }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private var weeklyDomain: ClosedRange<Date> {
        let cal = Calendar.current
        guard let start = weeklyDays.first,
              let end = cal.date(byAdding: .day, value: 7, to: start) else {
            return Date()...Date()
        }
        return start...end
    }

    // MARK: - Formatters

    private func pomodoroTimeRange(_ session: PomodoroSessionBreakdown) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        switch viewMode {
        case .daily:
            formatter.dateFormat = "HH:mm"
            return "\(formatter.string(from: session.startedAt))-\(formatter.string(from: session.endedAt))"
        case .weekly, .monthly:
            formatter.dateFormat = "M/d HH:mm"
            let start = formatter.string(from: session.startedAt)
            formatter.dateFormat = "HH:mm"
            return "\(start)-\(formatter.string(from: session.endedAt))"
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "\(s)s"
    }

    private func formatHours(_ hours: Double) -> String {
        if hours >= 1 {
            return String(format: "%.1fh", hours)
        }
        let minutes = Int(round(hours * 60))
        return "\(minutes)m"
    }

    private func percentLabel(_ value: Double, total: Double) -> String {
        guard total > 0 else { return "0%" }
        return String(format: "%.0f%%", value / total * 100)
    }

    private func dayLabel(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "M/d (E)"
        return fmt.string(from: date)
    }
}

// MARK: - Heatmap calendar

struct HeatmapCalendar: View {
    let dailyTotals: [Date: Double]
    let month: Date
    /// 휴가로 표시할 날짜들 (startOfDay 정규화). 비어있으면 일반 셀로 그려진다.
    var vacationDates: Set<Date> = []

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        let cells = monthCells
        let maxHours = max(1.0, dailyTotals.values.max() ?? 0)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(["월", "화", "수", "목", "금", "토", "일"], id: \.self) { w in
                    Text(w)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
                spacing: 4
            ) {
                ForEach(cells) { cell in
                    if let date = cell.date {
                        let key = calendar.startOfDay(for: date)
                        cellView(
                            date: date,
                            hours: dailyTotals[key] ?? 0,
                            maxHours: maxHours,
                            isVacation: vacationDates.contains(key)
                        )
                    } else {
                        Color.clear.frame(height: 44)
                    }
                }
            }
        }
    }

    private func cellView(date: Date, hours: Double, maxHours: Double, isVacation: Bool) -> some View {
        let intensity = min(1.0, hours / maxHours)
        let day = calendar.component(.day, from: date)
        let isToday = calendar.isDateInToday(date)
        let vacationOrange = Color.orange
        return VStack(spacing: 2) {
            HStack(spacing: 2) {
                Text("\(day)")
                    .font(.caption2.bold())
                    .foregroundStyle(intensity > 0.55 && !isVacation ? Color.white : Color.primary)
                if isVacation {
                    Text("🏖️")
                        .font(.system(size: 9))
                }
            }
            if hours > 0 {
                Text(hours >= 1 ? String(format: "%.1fh", hours) : "\(Int(round(hours * 60)))m")
                    .font(.system(size: 9))
                    .foregroundStyle(intensity > 0.55 && !isVacation ? Color.white.opacity(0.95) : Color.secondary)
                    .monospacedDigit()
            } else if isVacation {
                Text("휴가")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(vacationOrange)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    isVacation
                        ? vacationOrange.opacity(hours > 0 ? 0.14 + intensity * 0.18 : 0.16)
                        : Color.accentColor.opacity(hours > 0 ? 0.2 + intensity * 0.7 : 0.06)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(borderColor(isToday: isToday, isVacation: isVacation), lineWidth: borderWidth(isToday: isToday, isVacation: isVacation))
        )
    }

    private func borderColor(isToday: Bool, isVacation: Bool) -> Color {
        if isToday { return Color.accentColor }
        if isVacation { return Color.orange.opacity(0.45) }
        return Color.clear
    }

    private func borderWidth(isToday: Bool, isVacation: Bool) -> CGFloat {
        if isToday { return 1.5 }
        if isVacation { return 0.8 }
        return 0
    }

    private struct Cell: Identifiable {
        let id: Int
        let date: Date?
    }

    private var monthCells: [Cell] {
        var comps = calendar.dateComponents([.year, .month], from: month)
        comps.day = 1
        guard let firstOfMonth = calendar.date(from: comps),
              let range = calendar.range(of: .day, in: .month, for: firstOfMonth) else {
            return []
        }
        // Monday=1 ... Sunday=7
        let raw = calendar.component(.weekday, from: firstOfMonth) // Sun=1..Sat=7
        let mondayBased = ((raw + 5) % 7) + 1
        let leadingBlanks = mondayBased - 1
        var cells: [Cell] = []
        for i in 0..<leadingBlanks {
            cells.append(Cell(id: -1 - i, date: nil))
        }
        for day in range {
            if let d = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth) {
                cells.append(Cell(id: day, date: d))
            }
        }
        while cells.count % 7 != 0 {
            cells.append(Cell(id: 1000 + cells.count, date: nil))
        }
        return cells
    }
}
