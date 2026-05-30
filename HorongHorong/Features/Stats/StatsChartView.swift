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

private enum AttentionFeedbackVerdict: String, CaseIterable, Identifiable {
    case correct
    case unclear
    case wrong

    var id: String { rawValue }

    var label: String {
        switch self {
        case .correct: return "맞아요"
        case .unclear: return "애매해요"
        case .wrong: return "아니에요"
        }
    }

    var icon: String {
        switch self {
        case .correct: return "checkmark"
        case .unclear: return "questionmark"
        case .wrong: return "xmark"
        }
    }
}

private struct AttentionFeedbackNotice {
    let location: String
    let message: String
}

private enum AttentionFeedbackDedupStore {
    private static let key = "attention.feedback.submittedKeys.v1"

    static func contains(_ feedbackKey: String) -> Bool {
        submittedKeys.contains(feedbackKey)
    }

    static func insert(_ feedbackKey: String) {
        var keys = submittedKeys
        keys.insert(feedbackKey)
        UserDefaults.standard.set(Array(keys).sorted(), forKey: key)
    }

    private static var submittedKeys: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }
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
    /// 휴식 후 다음 흐름 선택 기록. 주의 전환 실패 판정에서 계획된 전환/외부 업무를 제외하는 데 사용한다.
    var breakTransitionIntents: [BreakTransitionIntent] = []
    /// 주간/월간 탭에서 원본 세그먼트 재집계를 피하기 위해 부모가 넘겨주는 집계 캐시.
    var aggregateSnapshot: StatsAggregateSnapshot? = nil
    /// 하루가 지난 뒤 확정 저장된 대표 주의 상태. 과거 날짜의 상태 점에 우선 사용한다.
    var attentionDaySummaries: [AttentionDaySummary] = []

    @State private var weeklySelection: Date? = nil
    @State private var dailyAngleSelection: Double? = nil
    @State private var attentionFeedbackNotice: AttentionFeedbackNotice? = nil
    /// 부모(StatsDetailWindow)가 미리 계산해서 넘겨주는 휴가 일자 집합. 차트가 직접 store 를 관찰하지 않도록 함.
    var vacationDays: Set<Date> = []

    @AppStorage(Constants.AppStorageKey.anonymousTelemetryEnabled)
    private var telemetryEnabled: Bool = false
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

                    dailyAttentionReviewCard
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

    private var dailyAttentionSummary: AttentionSummary {
        AttentionAnalytics.summary(
            for: referenceDate,
            segments: dailySegments.filter { !Constants.hiddenLegacyCategories.contains($0.category) },
            timerSessions: timerSessions,
            thresholds: AttentionThresholdStore.shared.thresholds,
            breakTransitions: breakTransitionIntents
        )
    }

    private var dailyAttentionReport: DailyAttentionReport {
        DailyAttentionReportBuilder.build(
            day: referenceDate,
            buckets: dailyBuckets,
            segments: dailySegments.filter { !Constants.hiddenLegacyCategories.contains($0.category) },
            timerSessions: timerSessions,
            attentionSummary: dailyAttentionSummary,
            thresholds: AttentionThresholdStore.shared.thresholds,
            isFinalized: isReferenceDateFinalized
        )
    }

    private var isReferenceDateFinalized: Bool {
        Calendar.current.startOfDay(for: referenceDate) < Calendar.current.startOfDay(for: Date())
    }

    private var dailyAttentionReviewCard: some View {
        let report = dailyAttentionReport
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(report.isFinalized ? "하루 회고" : "오늘 진행 중")
                        .font(.headline)
                        .foregroundStyle(PopoverChrome.ink)
                    Text(report.patternMessage)
                        .font(.caption)
                        .foregroundStyle(PopoverChrome.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                HStack(spacing: 5) {
                    Text(report.flowState.emoji)
                    Text(report.flowState.label)
                        .font(.caption.bold())
                }
                .foregroundStyle(PopoverChrome.ink)
                .padding(.vertical, 5)
                .padding(.horizontal, 9)
                .background(PopoverChrome.accentSoft.opacity(0.38), in: Capsule())
            }

            VStack(spacing: 8) {
                if let best = report.bestWindow {
                    dailyAttentionWindowRow(
                        icon: "sparkles",
                        title: report.isFinalized ? "가장 길게 이어진 몰입" : "지금까지 안정적인 구간",
                        window: best
                    )
                }

                if let worst = report.worstWindow {
                    dailyAttentionWindowRow(
                        icon: "waveform.path.ecg",
                        title: report.isFinalized ? "가장 흔들린 구간" : "지금까지 흔들린 구간",
                        window: worst
                    )
                }

                if let quick = report.quickRecovery {
                    dailyRecoveryRow(
                        icon: "arrow.uturn.backward.circle",
                        title: "복귀가 좋았던 순간",
                        moment: quick
                    )
                }

                if let difficult = report.difficultRecovery {
                    dailyRecoveryRow(
                        icon: "clock.badge.exclamationmark",
                        title: "복귀가 어려웠던 순간",
                        moment: difficult
                    )
                }

                if !report.hasReviewSignals {
                    Text(report.isFinalized ? "이 날은 회고할 만큼의 세부 타임라인이 부족해요." : "오늘은 아직 회고할 만큼의 세부 타임라인이 부족해요.")
                        .font(.caption)
                        .foregroundStyle(PopoverChrome.inkSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Divider()

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lightbulb")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PopoverChrome.accent)
                    .frame(width: 18)
                Text(report.guidanceMessage)
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            attentionFeedbackControls(
                eventName: "attention_daily_review_feedback",
                feedbackLocation: report.isFinalized ? "stats_daily_review_finalized" : "stats_daily_review_live",
                periodKey: dailyFeedbackPeriodKey(isFinalized: report.isFinalized),
                promptTitle: report.isFinalized ? "이 회고가 맞나요?" : "지금 흐름 해석이 맞나요?",
                flowState: report.flowState,
                signalType: dailyFeedbackSignalType,
                score: dailyAttentionSummary.overallScore
            )
        }
        .popoverCard(padding: 14)
    }

    private func dailyAttentionWindowRow(
        icon: String,
        title: String,
        window: DailyAttentionWindow
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(PopoverChrome.accent)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.caption.bold())
                        .foregroundStyle(PopoverChrome.ink)
                    Text(timeRangeText(from: window.start, to: window.end))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(PopoverChrome.inkTertiary)
                }
                Text(window.reason)
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func dailyRecoveryRow(
        icon: String,
        title: String,
        moment: DailyRecoveryMoment
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(PopoverChrome.accent)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.caption.bold())
                        .foregroundStyle(PopoverChrome.ink)
                    Text(timeText(moment.occurredAt))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(PopoverChrome.inkTertiary)
                }
                Text(moment.message)
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func attentionFeedbackControls(
        eventName: String,
        feedbackLocation: String,
        periodKey: String,
        promptTitle: String = "이 해석이 맞나요?",
        flowState: AttentionFlowState?,
        signalType: String?,
        score: Double?
    ) -> some View {
        let feedbackKey = attentionFeedbackKey(
            eventName: eventName,
            feedbackLocation: feedbackLocation,
            periodKey: periodKey
        )

        if AttentionFeedbackDedupStore.contains(feedbackKey) {
            if let notice = attentionFeedbackNotice, notice.location == feedbackLocation {
                Text(notice.message)
                    .font(.caption2)
                    .foregroundStyle(PopoverChrome.inkTertiary)
                    .padding(.top, 2)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(promptTitle)
                        .font(.caption.bold())
                        .foregroundStyle(PopoverChrome.ink)

                    Spacer(minLength: 8)

                    ForEach(AttentionFeedbackVerdict.allCases) { verdict in
                        Button {
                            submitAttentionFeedback(
                                verdict: verdict,
                                eventName: eventName,
                                feedbackLocation: feedbackLocation,
                                feedbackKey: feedbackKey,
                                flowState: flowState,
                                signalType: signalType,
                                score: score
                            )
                        } label: {
                            Label(verdict.label, systemImage: verdict.icon)
                                .labelStyle(.titleAndIcon)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!canSubmitAttentionFeedback)
                    }
                }

                if let notice = attentionFeedbackNotice, notice.location == feedbackLocation {
                    Text(notice.message)
                        .font(.caption2)
                        .foregroundStyle(PopoverChrome.inkTertiary)
                } else if !canSubmitAttentionFeedback {
                    Text(attentionFeedbackDisabledMessage)
                        .font(.caption2)
                        .foregroundStyle(PopoverChrome.inkTertiary)
                }
            }
            .padding(.top, 2)
        }
    }

    private var canSubmitAttentionFeedback: Bool {
        telemetryEnabled && TelemetryClient.shared.isConfigured
    }

    private var attentionFeedbackDisabledMessage: String {
        if TelemetryClient.shared.isConfigured {
            return "설정에서 익명 개선 데이터 보내기를 켜면 피드백을 보낼 수 있어요."
        }
        return "Supabase 연결값이 없어 피드백을 보낼 수 없어요."
    }

    private func submitAttentionFeedback(
        verdict: AttentionFeedbackVerdict,
        eventName: String,
        feedbackLocation: String,
        feedbackKey: String,
        flowState: AttentionFlowState?,
        signalType: String?,
        score: Double?
    ) {
        guard canSubmitAttentionFeedback else {
            attentionFeedbackNotice = AttentionFeedbackNotice(
                location: feedbackLocation,
                message: attentionFeedbackDisabledMessage
            )
            return
        }

        attentionFeedbackNotice = AttentionFeedbackNotice(
            location: feedbackLocation,
            message: "전송 중..."
        )

        Task {
            let didSubmit = await TelemetryClient.shared.submitAttentionFeedback(
                eventName: eventName,
                feedbackLocation: feedbackLocation,
                flowState: flowState?.rawValue,
                signalType: signalType,
                verdict: verdict.rawValue,
                thresholdPreset: AttentionThresholdStore.shared.sensitivity.rawValue,
                scoreBucket: attentionScoreBucket(score),
                sanitizedComment: nil
            )

            await MainActor.run {
                if didSubmit {
                    AttentionFeedbackDedupStore.insert(feedbackKey)
                }
                attentionFeedbackNotice = AttentionFeedbackNotice(
                    location: feedbackLocation,
                    message: didSubmit ? "감사합니다. 작업에 몰입할 수 있도록 개선하는 데 활용하겠습니다." : "전송에 실패했어요. 잠시 후 다시 시도해 주세요."
                )
                if didSubmit {
                    scheduleAttentionFeedbackNoticeClear(location: feedbackLocation)
                }
            }
        }
    }

    private func scheduleAttentionFeedbackNoticeClear(location: String) {
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await MainActor.run {
                if attentionFeedbackNotice?.location == location {
                    attentionFeedbackNotice = nil
                }
            }
        }
    }

    private var dailyFeedbackSignalType: String {
        guard let primary = dailyAttentionSummary.primaryEvent else { return "general" }
        return feedbackSignalType(for: primary.type)
    }

    private func attentionFeedbackKey(eventName: String, feedbackLocation: String, periodKey: String) -> String {
        [eventName, feedbackLocation, periodKey].joined(separator: ":")
    }

    private func dailyFeedbackPeriodKey(isFinalized: Bool) -> String {
        let prefix = isFinalized ? "day-finalized" : "day-live"
        return "\(prefix)-\(dayKey(referenceDate))"
    }

    private var weeklyFeedbackPeriodKey: String {
        let weekStart = Constants.mondayWeekStart(for: referenceDate)
        return "week-\(dayKey(weekStart))"
    }

    private var isReferenceWeekFinalized: Bool {
        let referenceWeekStart = Constants.mondayWeekStart(for: referenceDate)
        let currentWeekStart = Constants.mondayWeekStart(for: Date())
        return referenceWeekStart < currentWeekStart
    }

    private var monthlyFeedbackPeriodKey: String {
        let monthStart = referenceMonthStart
        return "month-\(dayKey(monthStart))"
    }

    private var referenceMonthStart: Date {
        let calendar = Calendar.current
        return calendar.date(from: calendar.dateComponents([.year, .month], from: referenceDate))
            ?? calendar.startOfDay(for: referenceDate)
    }

    private var isReferenceMonthFinalized: Bool {
        referenceMonthStart < currentMonthStart
    }

    private var currentMonthStart: Date {
        let calendar = Calendar.current
        return calendar.date(from: calendar.dateComponents([.year, .month], from: Date()))
            ?? calendar.startOfDay(for: Date())
    }

    private func dayKey(_ date: Date) -> String {
        Self.periodKeyFormatter.string(from: Calendar.current.startOfDay(for: date))
    }

    private var weeklyFeedbackSignalType: String {
        let report = weeklyAttentionTrendReport
        guard report.hasComparableData else { return "insufficient_data" }
        if let declinedSignal = report.metrics
            .filter({ isDeclined($0.direction) })
            .compactMap({ feedbackSignalType(for: $0) })
            .first {
            return declinedSignal
        }
        if let improvedSignal = report.metrics
            .filter({ isImproved($0.direction) })
            .compactMap({ feedbackSignalType(for: $0) })
            .first {
            return improvedSignal
        }
        return "general"
    }

    private var monthlyFeedbackSignalType: String {
        let report = monthlyAttentionPatternReport
        guard report.hasCurrentData else { return "insufficient_data" }
        if let repeated = report.patterns.first(where: { $0.title == "반복 신호" }),
           let signalType = feedbackSignalType(for: repeated) {
            return signalType
        }
        return "general"
    }

    private func feedbackSignalType(for type: AttentionEventType) -> String {
        switch type {
        case .selectiveDistraction: return "selective"
        case .sustainedDrop: return "sustained"
        case .delayedReturn: return "switching"
        case .allowedSwitch: return "general"
        }
    }

    private func feedbackSignalType(for metric: AttentionTrendMetric) -> String? {
        switch metric.title {
        case "방해 앱 체류": return "selective"
        case "조기 중단": return "sustained"
        case "복귀 지연": return "switching"
        default: return nil
        }
    }

    private func feedbackSignalType(for pattern: MonthlyAttentionPattern) -> String? {
        if pattern.value.contains("방해 앱") { return "selective" }
        if pattern.value.contains("조기 중단") { return "sustained" }
        if pattern.value.contains("복귀 지연") { return "switching" }
        return nil
    }

    private func isDeclined(_ direction: AttentionTrendDirection) -> Bool {
        if case .declined = direction { return true }
        return false
    }

    private func isImproved(_ direction: AttentionTrendDirection) -> Bool {
        if case .improved = direction { return true }
        return false
    }

    private func attentionScoreBucket(_ score: Double?) -> String? {
        guard let score else { return nil }
        let clamped = min(max(score, 0), 1)
        let bucketStart = Int(floor(clamped * 10) * 10)
        let bucketEnd = min(bucketStart + 9, 100)
        return "\(bucketStart)-\(bucketEnd)"
    }

    private func scoreValue(from text: String) -> Double? {
        let digits = text.filter(\.isNumber)
        guard let value = Double(digits) else { return nil }
        return min(max(value / 100, 0), 1)
    }

    private static let periodKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

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
                    weeklyAttentionTrendCard
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
            Text("🌿 흐름 유지 · 〰️ 흐름 변동 · ↩️ 복귀 필요")
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

    private var weeklyAttentionTrendReport: WeeklyAttentionTrendReport {
        guard let weekStart = weeklyDays.first else {
            return WeeklyAttentionTrendReportBuilder.build(weekStart: referenceDate, summaries: [])
        }
        return WeeklyAttentionTrendReportBuilder.build(
            weekStart: weekStart,
            summaries: attentionDaySummaries
        )
    }

    private var weeklyAttentionTrendCard: some View {
        let report = weeklyAttentionTrendReport
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("지난 주와 비교")
                        .font(.headline)
                        .foregroundStyle(PopoverChrome.ink)
                    Text(report.summaryMessage)
                        .font(.caption)
                        .foregroundStyle(PopoverChrome.inkSecondary)
                }
                Spacer()
                Text("이번 \(report.currentDayCount)일 · 지난 \(report.previousDayCount)일")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(PopoverChrome.inkTertiary)
            }

            if report.hasComparableData {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 8)], spacing: 8) {
                    ForEach(report.metrics) { metric in
                        weeklyTrendMetricCard(metric)
                    }
                }
            } else {
                Text("비교 가능한 확정 회고가 아직 부족해요. 하루가 지나 확정된 기록이 쌓이면 변화가 표시됩니다.")
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "scope")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PopoverChrome.accent)
                    .frame(width: 18)
                Text(report.guidanceMessage)
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if report.hasComparableData, isReferenceWeekFinalized {
                attentionFeedbackControls(
                    eventName: "attention_weekly_trend_feedback",
                    feedbackLocation: "stats_weekly_trend",
                    periodKey: weeklyFeedbackPeriodKey,
                    flowState: nil,
                    signalType: weeklyFeedbackSignalType,
                    score: nil
                )
            }
        }
        .popoverCard(padding: 14)
    }

    private func weeklyTrendMetricCard(_ metric: AttentionTrendMetric) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let icon = trendIcon(metric.direction) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(trendColor(metric.direction))
                }
                Text(metric.title)
                    .font(.caption.bold())
                    .foregroundStyle(PopoverChrome.ink)
                Spacer(minLength: 0)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(metric.currentValueText)
                    .font(.callout.bold())
                    .monospacedDigit()
                    .foregroundStyle(PopoverChrome.ink)
                Text("지난 \(metric.previousValueText)")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(PopoverChrome.inkTertiary)
            }
            Text(metric.message)
                .font(.caption2)
                .foregroundStyle(PopoverChrome.inkSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(PopoverChrome.surfaceAlt.opacity(0.72), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func trendIcon(_ direction: AttentionTrendDirection) -> String? {
        switch direction {
        case .improved: return "arrow.up.right"
        case .declined: return "arrow.down.right"
        case .steady: return nil
        }
    }

    private func trendColor(_ direction: AttentionTrendDirection) -> Color {
        switch direction {
        case .improved: return .green
        case .declined: return .orange
        case .steady: return PopoverChrome.inkTertiary
        }
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
                        weekdayAxisLabel(date: date, state: focusByDay[key] ?? .noRecord)
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

    private func weekdayAxisLabel(date: Date, state: AttentionFlowState) -> some View {
        VStack(spacing: 3) {
            Text(weekdayShortLabel(date))
                .font(.caption2)
            Circle()
                .fill(focusDotColor(state))
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

    private func focusDotColor(_ state: AttentionFlowState) -> Color {
        switch state {
        case .steady: return .green
        case .variable: return .yellow
        case .returnNeeded: return .red
        case .noRecord: return Color.secondary.opacity(0.25)
        }
    }

    private var weeklyFocusByDay: [Date: AttentionFlowState] {
        let startedAt = Date()
        let recorded = attentionDaySummaries.reduce(into: [:]) { result, summary in
            result[Calendar.current.startOfDay(for: summary.day)] = summary.flowState
        }
        if hasAggregateSource, let aggregateSnapshot, !aggregateSnapshot.dailyFocusLevels.isEmpty {
            var result = Dictionary(uniqueKeysWithValues: aggregateSnapshot.dailyFocusLevels.map {
                ($0.day, AttentionFlowState.fromLegacyValue($0.level))
            })
            result.merge(recorded) { _, recorded in recorded }
            logChartBuild("weeklyFocusByDay", rows: result.count, startedAt: startedAt, source: "aggregate")
            return result
        }

        let cal = Calendar.current
        var result: [Date: AttentionFlowState] = recorded
        for day in weeklyDays {
            if result[day] != nil { continue }
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
            result[day] = sum.flowState
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
                    monthlyAttentionPatternCard
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

    private var monthlyAttentionPatternReport: MonthlyAttentionPatternReport {
        return MonthlyAttentionPatternReportBuilder.build(
            monthStart: referenceMonthStart,
            summaries: attentionDaySummaries
        )
    }

    private var monthlyAttentionPatternCard: some View {
        let report = monthlyAttentionPatternReport
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("월간 집중 패턴")
                        .font(.headline)
                        .foregroundStyle(PopoverChrome.ink)
                    Text(report.summaryMessage)
                        .font(.caption)
                        .foregroundStyle(PopoverChrome.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Text("이번 \(report.currentDayCount)일 · 지난 \(report.previousDayCount)일")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(PopoverChrome.inkTertiary)
            }

            if report.hasCurrentData {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 8)], spacing: 8) {
                    if let trend = report.scoreTrend {
                        weeklyTrendMetricCard(trend)
                    }
                    ForEach(report.patterns) { pattern in
                        monthlyPatternCard(pattern)
                    }
                }
            } else {
                Text("하루가 지나 확정된 기록이 쌓이면 강한 요일, 주의할 요일, 반복되는 신호가 표시됩니다.")
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PopoverChrome.accent)
                    .frame(width: 18)
                Text(report.guidanceMessage)
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isReferenceMonthFinalized, report.hasCurrentData {
                attentionFeedbackControls(
                    eventName: "attention_monthly_pattern_feedback",
                    feedbackLocation: "stats_monthly_pattern",
                    periodKey: monthlyFeedbackPeriodKey,
                    flowState: nil,
                    signalType: monthlyFeedbackSignalType,
                    score: report.scoreTrend.flatMap { scoreValue(from: $0.currentValueText) }
                )
            }
        }
        .popoverCard(padding: 14)
    }

    private func monthlyPatternCard(_ pattern: MonthlyAttentionPattern) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(pattern.title)
                .font(.caption.bold())
                .foregroundStyle(PopoverChrome.ink)
            Text(pattern.value)
                .font(.callout.bold())
                .foregroundStyle(PopoverChrome.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text(pattern.message)
                .font(.caption2)
                .foregroundStyle(PopoverChrome.inkSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(PopoverChrome.surfaceAlt.opacity(0.72), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
            let start = Constants.mondayWeekStart(for: referenceDate, calendar: calendar)
            guard let end = calendar.date(byAdding: .day, value: 7, to: start) else {
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
        let weekStart = Constants.mondayWeekStart(for: referenceDate, calendar: cal)
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

    private func timeRangeText(from start: Date, to end: Date) -> String {
        "\(timeText(start))-\(timeText(end))"
    }

    private func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
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
