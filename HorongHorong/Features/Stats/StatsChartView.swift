import SwiftUI
import Charts
import SwiftData

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

    @State private var weeklySelection: Date? = nil
    @State private var dailyAngleSelection: Double? = nil

    @AppStorage(Constants.AppStorageKey.timelineStartHour)
    private var timelineStartHour: Int = Constants.defaultTimelineStartHour
    @AppStorage(Constants.AppStorageKey.timelineEndHour)
    private var timelineEndHour: Int = Constants.defaultTimelineEndHour
    @AppStorage(Constants.AppStorageKey.timelineBucketMinutes)
    private var timelineBucketMinutes: Int = Constants.defaultTimelineBucketMinutes

    private var activeRecords: [AppUsageRecord] {
        records.filter { !Constants.hiddenLegacyCategories.contains($0.category) }
    }

    private var activeSegments: [AppUsageSegment] {
        periodSegments.filter { !Constants.hiddenLegacyCategories.contains($0.category) }
    }

    private var hasSegmentSource: Bool {
        !activeSegments.isEmpty
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
            if categoryData.isEmpty {
                noDataView
            } else {
                DailyFocusSummaryCard(summary: dailySummary)

                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        donutChart(data: categoryData)
                            .frame(width: 220)
                        categoryLegend(data: categoryData)
                            .frame(maxWidth: 260)
                    }
                    .frame(width: 280, alignment: .top)

                    DailyTimelineBucketsView(
                        buckets: displayBuckets,
                        bucketSeconds: displayBucketSeconds,
                        emptyTitle: timelineEmptyTitle,
                        emptyDetail: timelineEmptyDetail
                    )
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }

                Divider()
                categoryBreakdownSection
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
        if dailySegments.isEmpty, !activeRecords.isEmpty {
            return recordBackedDailySummary
        }
        return TimelineAnalytics.summary(
            for: referenceDate,
            segments: dailySegments,
            buckets: dailyBuckets,
            timerSessions: timerSessions
        )
    }

    private var recordBackedDailySummary: DailyFocusSummary {
        var totals: [String: Int] = [:]
        for record in activeRecords {
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
        return "총 사용 시간과 별도로 저장되며, 앱 전환/종료 이후의 기록부터 표시됩니다"
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
                Text(formatHours(item.hours))
                    .font(.caption)
                    .monospacedDigit()
                Text(percentLabel(item.hours, total: total))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                Text("총 사용 시간")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(formatHours(total))
                    .font(.title3.bold())
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
                    Spacer(minLength: 4)
                    Text(formatHours(item.hours))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Text(percentLabel(item.hours, total: total))
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            ForEach(categoryBreakdownData) { group in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Constants.categoryColor(for: group.category))
                            .frame(width: 10, height: 10)
                        Text(Constants.categoryEmoji(for: group.category))
                        Text(group.category)
                            .font(.callout.bold())
                        Spacer()
                        Text(formatDuration(group.totalSeconds))
                            .font(.callout.bold())
                            .monospacedDigit()
                    }
                    ForEach(group.apps) { app in
                        HStack {
                            Text(app.appName)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 22)
                            Spacer()
                            Text(formatDuration(app.durationSeconds))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                .padding(.vertical, 4)
                Divider()
            }
        }
    }

    // MARK: - Weekly

    private var weeklyView: some View {
        VStack(alignment: .leading, spacing: 16) {
            if weeklyStackedData.isEmpty {
                noDataView
            } else {
                weeklyTooltipPanel
                weeklyFocusLegend
                weeklyStackedChart
                categoryLegend(data: categoryData)
                Divider()
                weeklyCategoryTotals
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
                .foregroundStyle(.secondary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
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
                Spacer()
                Text(formatHours(total))
                    .font(.caption.bold())
                    .monospacedDigit()
            }
            if items.isEmpty {
                Text("기록 없음")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Constants.categoryColor(for: item.category))
                            .frame(width: 8, height: 8)
                        Text(item.category).font(.caption)
                        Spacer(minLength: 8)
                        Text(formatHours(item.hours))
                            .font(.caption)
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
        .frame(minWidth: 160)
    }

    private var weeklyCategoryTotals: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("이번 주 카테고리 합계")
                .font(.headline)
            ForEach(categoryData) { item in
                HStack(spacing: 8) {
                    Circle()
                        .fill(item.color)
                        .frame(width: 10, height: 10)
                    Text(Constants.categoryEmoji(for: item.category))
                    Text(item.category).font(.callout)
                    Spacer()
                    Text(formatHours(item.hours))
                        .font(.callout)
                        .monospacedDigit()
                }
            }
        }
    }

    // MARK: - Monthly

    private var monthlyView: some View {
        VStack(alignment: .leading, spacing: 24) {
            if categoryData.isEmpty {
                noDataView
            } else {
                monthlyHeatmapSection
                Divider()
                monthlyCategorySection
                Divider()
                monthlyTopAppsSection
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
                Spacer()
                Text("총 \(formatHours(total)) · 사용한 날 \(active)일 · 일평균 \(formatHours(avg))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HeatmapCalendar(dailyTotals: totals, month: referenceDate)
        }
    }

    private var monthlyCategorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("카테고리 분포")
                .font(.headline)
            HStack(alignment: .top, spacing: 16) {
                donutChart(data: categoryData)
                    .frame(width: 220)
                categoryLegend(data: categoryData)
            }
        }
    }

    private var monthlyTopAppsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top 10 앱")
                .font(.headline)
            ForEach(Array(appDetails.prefix(10).enumerated()), id: \.offset) { idx, app in
                HStack {
                    Text("\(idx + 1)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 22, alignment: .trailing)
                    Text(Constants.categoryEmoji(for: app.category))
                    Text(app.appName).font(.callout)
                    Spacer()
                    Text(app.category)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formatDuration(app.durationSeconds))
                        .font(.callout)
                        .monospacedDigit()
                }
            }
        }
    }

    // MARK: - Empty state

    private var noDataView: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("해당 기간에 기록된 데이터가 없습니다")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    // MARK: - Derived data

    private var categoryData: [ChartCategoryData] {
        let durations = hasSegmentSource ? segmentDurationsByCategory : recordDurationsByCategory
        return durations
            .sorted {
                if $0.value != $1.value { return $0.value > $1.value }
                return $0.key < $1.key
            }
            .map { ChartCategoryData(
                category: $0.key,
                hours: Double($0.value) / 3600.0,
                color: Constants.categoryColor(for: $0.key)
            )}
    }

    private var appDetails: [(appName: String, category: String, durationSeconds: Int)] {
        var details: [String: (category: String, duration: Int)] = [:]
        if hasSegmentSource {
            for segment in activeSegments {
                let duration = clippedDuration(segment)
                guard duration > 0 else { continue }
                if let existing = details[segment.appName] {
                    details[segment.appName] = (existing.category, existing.duration + duration)
                } else {
                    details[segment.appName] = (segment.category, duration)
                }
            }
        } else {
            for record in activeRecords {
                if let existing = details[record.appName] {
                    details[record.appName] = (existing.category, existing.duration + record.durationSeconds)
                } else {
                    details[record.appName] = (record.category, record.durationSeconds)
                }
            }
        }
        return details
            .sorted { $0.value.duration > $1.value.duration }
            .map { (appName: $0.key, category: $0.value.category, durationSeconds: $0.value.duration) }
    }

    private var categoryBreakdownData: [CategoryAppsBreakdown] {
        var groups: [String: [String: Int]] = [:]
        if hasSegmentSource {
            for segment in activeSegments {
                let duration = clippedDuration(segment)
                guard duration > 0 else { continue }
                groups[segment.category, default: [:]][segment.appName, default: 0] += duration
            }
        } else {
            for record in activeRecords {
                groups[record.category, default: [:]][record.appName, default: 0] += record.durationSeconds
            }
        }
        return groups
            .map { (cat, apps) in
                let total = apps.values.reduce(0, +)
                let appList = apps
                    .sorted { $0.value > $1.value }
                    .map { AppUsageEntry(appName: $0.key, durationSeconds: $0.value) }
                return CategoryAppsBreakdown(category: cat, totalSeconds: total, apps: appList)
            }
            .sorted { $0.totalSeconds > $1.totalSeconds }
    }

    private var recordDurationsByCategory: [String: Int] {
        var durations: [String: Int] = [:]
        for record in activeRecords {
            durations[record.category, default: 0] += record.durationSeconds
        }
        return durations
    }

    private var segmentDurationsByCategory: [String: Int] {
        var durations: [String: Int] = [:]
        for segment in activeSegments {
            let duration = clippedDuration(segment)
            guard duration > 0 else { continue }
            durations[segment.category, default: 0] += duration
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

    private var dailySegmentCategoryData: [DailyChartData] {
        var grouped: [Date: [String: Int]] = [:]
        for day in weeklyDays {
            for segment in activeSegments {
                let seconds = clippedDuration(segment, in: day)
                guard seconds > 0 else { continue }
                grouped[day, default: [:]][segment.category, default: 0] += seconds
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
        for record in activeRecords {
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
        var totals: [Date: Int] = [:]
        guard let bounds = periodBounds else { return [:] }
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: bounds.start)
        while day < bounds.end {
            for segment in activeSegments {
                let seconds = clippedDuration(segment, in: day)
                guard seconds > 0 else { continue }
                totals[day, default: 0] += seconds
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return totals.mapValues { Double($0) / 3600.0 }
    }

    private var dailyRecordTotalsMap: [Date: Double] {
        var totals: [Date: Int] = [:]
        for record in activeRecords {
            let day = Calendar.current.startOfDay(for: record.date)
            totals[day, default: 0] += record.durationSeconds
        }
        return totals.mapValues { Double($0) / 3600.0 }
    }

    private var weeklyStackedData: [DailyChartData] {
        hasSegmentSource ? dailySegmentCategoryData : dailyRecordCategoryData
    }

    private var monthlyDailyTotalsMap: [Date: Double] {
        hasSegmentSource ? dailySegmentTotalsMap : dailyRecordTotalsMap
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

    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
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
                        cellView(date: date, hours: dailyTotals[key] ?? 0, maxHours: maxHours)
                    } else {
                        Color.clear.frame(height: 44)
                    }
                }
            }
        }
    }

    private func cellView(date: Date, hours: Double, maxHours: Double) -> some View {
        let intensity = min(1.0, hours / maxHours)
        let day = calendar.component(.day, from: date)
        let isToday = calendar.isDateInToday(date)
        return VStack(spacing: 2) {
            Text("\(day)")
                .font(.caption2.bold())
                .foregroundStyle(intensity > 0.55 ? Color.white : Color.primary)
            if hours > 0 {
                Text(hours >= 1 ? String(format: "%.1fh", hours) : "\(Int(round(hours * 60)))m")
                    .font(.system(size: 9))
                    .foregroundStyle(intensity > 0.55 ? Color.white.opacity(0.95) : Color.secondary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.accentColor.opacity(hours > 0 ? 0.2 + intensity * 0.7 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isToday ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
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
