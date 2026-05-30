import Foundation

struct DailyAttentionWindow: Identifiable, Equatable {
    enum Kind {
        case best
        case worst
    }

    var id: String { "\(kind)-\(Int(start.timeIntervalSince1970))" }
    let kind: Kind
    let start: Date
    let end: Date
    let primaryCategory: String?
    let score: Double
    let durationSeconds: Int
    let switches: Int
    let reason: String
}

struct DailyRecoveryMoment: Identifiable, Equatable {
    enum Kind {
        case quickReturn
        case delayedReturn
    }

    var id: String { "\(kind)-\(Int(occurredAt.timeIntervalSince1970))" }
    let kind: Kind
    let occurredAt: Date
    let durationSeconds: Int
    let category: String?
    let message: String
}

struct DailyAttentionReport {
    let day: Date
    let isFinalized: Bool
    let flowState: AttentionFlowState
    let bestWindow: DailyAttentionWindow?
    let worstWindow: DailyAttentionWindow?
    let quickRecovery: DailyRecoveryMoment?
    let difficultRecovery: DailyRecoveryMoment?
    let patternMessage: String
    let guidanceMessage: String

    var hasReviewSignals: Bool {
        bestWindow != nil || worstWindow != nil || quickRecovery != nil || difficultRecovery != nil
    }
}

enum AttentionTrendDirection {
    case improved
    case declined
    case steady
}

struct AttentionTrendMetric: Identifiable {
    var id: String { title }
    let title: String
    let currentValueText: String
    let previousValueText: String
    let direction: AttentionTrendDirection
    let message: String
}

struct WeeklyAttentionTrendReport {
    let currentDayCount: Int
    let previousDayCount: Int
    let metrics: [AttentionTrendMetric]
    let summaryMessage: String
    let guidanceMessage: String

    var hasComparableData: Bool {
        currentDayCount > 0 && previousDayCount > 0 && !metrics.isEmpty
    }
}

struct MonthlyAttentionPattern: Identifiable {
    var id: String { title }
    let title: String
    let value: String
    let message: String
}

struct MonthlyAttentionPatternReport {
    let currentDayCount: Int
    let previousDayCount: Int
    let summaryMessage: String
    let guidanceMessage: String
    let scoreTrend: AttentionTrendMetric?
    let patterns: [MonthlyAttentionPattern]

    var hasCurrentData: Bool {
        currentDayCount > 0
    }
}

enum MonthlyAttentionPatternReportBuilder {
    static func build(
        monthStart: Date,
        summaries: [AttentionDaySummary]
    ) -> MonthlyAttentionPatternReport {
        let calendar = Calendar.current
        guard let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart),
              let previousStart = calendar.date(byAdding: .month, value: -1, to: monthStart) else {
            return emptyReport
        }

        let current = summaries.filter { $0.day >= monthStart && $0.day < monthEnd }
        let previous = summaries.filter { $0.day >= previousStart && $0.day < monthStart }

        guard !current.isEmpty else {
            return MonthlyAttentionPatternReport(
                currentDayCount: 0,
                previousDayCount: previous.count,
                summaryMessage: "이번 달 확정 회고가 아직 없어요.",
                guidanceMessage: "하루가 지나 확정된 기록이 쌓이면 요일별 강점과 반복되는 흔들림을 보여줄게요.",
                scoreTrend: nil,
                patterns: []
            )
        }

        let bestWeekday = weekdayPattern(
            title: "강한 요일",
            summaries: current,
            chooseMax: true
        )
        let weakWeekday = weekdayPattern(
            title: "주의할 요일",
            summaries: current,
            chooseMax: false
        )
        let dominantSignal = dominantSignalPattern(current)
        let trend = previous.isEmpty ? nil : scoreTrend(current: current, previous: previous)
        let patterns = [bestWeekday, weakWeekday, dominantSignal].compactMap { $0 }

        return MonthlyAttentionPatternReport(
            currentDayCount: current.count,
            previousDayCount: previous.count,
            summaryMessage: summaryMessage(
                current: current,
                previous: previous,
                bestWeekday: bestWeekday,
                weakWeekday: weakWeekday,
                trend: trend
            ),
            guidanceMessage: guidanceMessage(
                bestWeekday: bestWeekday,
                weakWeekday: weakWeekday,
                dominantSignal: dominantSignal,
                trend: trend
            ),
            scoreTrend: trend,
            patterns: patterns
        )
    }

    private static var emptyReport: MonthlyAttentionPatternReport {
        MonthlyAttentionPatternReport(
            currentDayCount: 0,
            previousDayCount: 0,
            summaryMessage: "월간 패턴을 계산할 기록이 아직 없어요.",
            guidanceMessage: "며칠 더 기록이 쌓이면 요일별 강점과 반복되는 흔들림을 보여줄게요.",
            scoreTrend: nil,
            patterns: []
        )
    }

    private static func weekdayPattern(
        title: String,
        summaries: [AttentionDaySummary],
        chooseMax: Bool
    ) -> MonthlyAttentionPattern? {
        let grouped = Dictionary(grouping: summaries) {
            Calendar.current.component(.weekday, from: $0.day)
        }
        let scored = grouped.map { weekday, items in
            let average = averageScore(items)
            return (weekday: weekday, average: average, count: items.count)
        }
        guard let selected = scored.min(by: { lhs, rhs in
            if lhs.average != rhs.average {
                return chooseMax ? lhs.average > rhs.average : lhs.average < rhs.average
            }
            return lhs.count > rhs.count
        }) else {
            return nil
        }

        let label = weekdayLabel(selected.weekday)
        let scoreText = "\(Int(round(selected.average * 100)))점"
        let message: String
        if chooseMax {
            message = "\(label)은 평균 흐름 점수가 가장 높았어요."
        } else {
            message = "\(label)은 흐름이 가장 자주 흔들린 편이에요."
        }

        return MonthlyAttentionPattern(
            title: title,
            value: "\(label) · \(scoreText)",
            message: message
        )
    }

    private static func dominantSignalPattern(_ summaries: [AttentionDaySummary]) -> MonthlyAttentionPattern? {
        let selective = summaries.reduce(0) { $0 + $1.selectiveEventCount }
        let sustained = summaries.reduce(0) { $0 + $1.sustainedEventCount }
        let delayedReturn = summaries.reduce(0) { $0 + $1.returnEventCount }
        let candidates = [
            (title: "방해 앱 체류", count: selective, message: "중요하지 않은 앱에 머문 신호가 가장 자주 보였어요."),
            (title: "조기 중단", count: sustained, message: "목표 시간보다 일찍 멈춘 신호가 가장 자주 보였어요."),
            (title: "복귀 지연", count: delayedReturn, message: "휴식 후 돌아오는 시간이 가장 큰 변수였어요."),
        ]
        guard let top = candidates.max(by: { $0.count < $1.count }),
              top.count > 0 else {
            return MonthlyAttentionPattern(
                title: "반복 신호",
                value: "뚜렷한 반복 없음",
                message: "이번 달은 특정 주의 신호가 강하게 반복되지는 않았어요."
            )
        }

        return MonthlyAttentionPattern(
            title: "반복 신호",
            value: "\(top.title) \(top.count)회",
            message: top.message
        )
    }

    private static func scoreTrend(
        current: [AttentionDaySummary],
        previous: [AttentionDaySummary]
    ) -> AttentionTrendMetric {
        let currentScore = averageScore(current) * 100
        let previousScore = averageScore(previous) * 100
        let diff = currentScore - previousScore
        let direction: AttentionTrendDirection
        let message: String
        if abs(diff) < 4 {
            direction = .steady
            message = "지난 달과 비슷한 흐름이에요."
        } else if diff > 0 {
            direction = .improved
            message = "지난 달보다 평균 흐름이 좋아졌어요."
        } else {
            direction = .declined
            message = "지난 달보다 평균 흐름이 낮아졌어요."
        }

        return AttentionTrendMetric(
            title: "월 평균 흐름",
            currentValueText: "\(Int(round(currentScore)))점",
            previousValueText: "\(Int(round(previousScore)))점",
            direction: direction,
            message: message
        )
    }

    private static func summaryMessage(
        current: [AttentionDaySummary],
        previous: [AttentionDaySummary],
        bestWeekday: MonthlyAttentionPattern?,
        weakWeekday: MonthlyAttentionPattern?,
        trend: AttentionTrendMetric?
    ) -> String {
        if let bestWeekday, let weakWeekday {
            return "이번 달은 \(bestWeekday.value) 흐름이 강했고, \(weakWeekday.value)에는 조정 여지가 보여요."
        }
        if trend != nil {
            return "이번 달 확정 회고 \(current.count)일을 바탕으로 패턴을 보고 있어요. 전월 비교는 보조 지표로 함께 표시됩니다."
        }
        return "이번 달 확정 회고 \(current.count)일을 바탕으로 패턴을 보고 있어요."
    }

    private static func guidanceMessage(
        bestWeekday: MonthlyAttentionPattern?,
        weakWeekday: MonthlyAttentionPattern?,
        dominantSignal: MonthlyAttentionPattern?,
        trend: AttentionTrendMetric?
    ) -> String {
        if dominantSignal?.value.hasPrefix("복귀 지연") == true {
            return "다음 달에는 휴식 뒤 첫 행동을 정해두는 게 핵심이에요. 휴식 전에 돌아올 화면과 다음 작업 한 줄을 남겨두세요."
        }
        if dominantSignal?.value.hasPrefix("방해 앱 체류") == true {
            return "다음 달에는 알림과 메시지 확인 시간을 집중 타이머가 끝난 뒤로 정해보세요. 중요한 작업은 방해 앱을 열기 전에 먼저 시작하는 편이 좋아요."
        }
        if dominantSignal?.value.hasPrefix("조기 중단") == true {
            return "다음 달에는 집중 타이머 1회 길이를 조금 줄여도 괜찮아요. 완료 가능한 길이로 끝까지 닫는 경험을 먼저 늘리는 편이 안정적입니다."
        }
        if trend?.direction == .declined {
            return "다음 달에는 중요한 작업을 가장 강한 요일에 몰아두고, 흔들린 요일에는 짧은 집중 타이머로 시작해보세요."
        }
        if let bestWeekday {
            return "\(bestWeekday.value) 패턴이 좋아요. 다음 달 중요한 작업은 이 요일 주변에 먼저 배치해보세요."
        }
        return "다음 달에도 같은 시간대에 첫 집중 타이머를 고정하면 장기 패턴이 더 선명해져요."
    }

    private static func averageScore(_ summaries: [AttentionDaySummary]) -> Double {
        guard !summaries.isEmpty else { return 0 }
        return summaries.reduce(0.0) { $0 + $1.overallScore } / Double(summaries.count)
    }

    private static func weekdayLabel(_ weekday: Int) -> String {
        let symbols = ["일", "월", "화", "수", "목", "금", "토"]
        guard weekday >= 1 && weekday <= symbols.count else { return "요일" }
        return "\(symbols[weekday - 1])요일"
    }
}

enum WeeklyAttentionTrendReportBuilder {
    static func build(
        weekStart: Date,
        summaries: [AttentionDaySummary]
    ) -> WeeklyAttentionTrendReport {
        let calendar = Calendar.current
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart),
              let previousStart = calendar.date(byAdding: .day, value: -7, to: weekStart) else {
            return emptyReport
        }

        let current = summaries.filter { $0.day >= weekStart && $0.day < weekEnd }
        let previous = summaries.filter { $0.day >= previousStart && $0.day < weekStart }

        guard !current.isEmpty, !previous.isEmpty else {
            return WeeklyAttentionTrendReport(
                currentDayCount: current.count,
                previousDayCount: previous.count,
                metrics: [],
                summaryMessage: "비교하려면 이번 주와 지난 주 기록이 모두 필요해요.",
                guidanceMessage: "며칠 더 기록이 쌓이면 전보다 나아진 점과 흔들린 점을 비교해볼 수 있어요."
            )
        }

        let metrics = [
            higherIsBetterMetric(
                title: "평균 흐름 점수",
                current: averageScore(current),
                previous: averageScore(previous),
                unit: "점",
                improvedMessage: "지난 주보다 흐름 유지가 좋아졌어요.",
                declinedMessage: "지난 주보다 흐름 점수가 낮아졌어요.",
                steadyMessage: "지난 주와 비슷한 흐름을 유지했어요."
            ),
            lowerIsBetterMetric(
                title: "방해 앱 체류",
                current: average(\.selectiveEventCount, in: current),
                previous: average(\.selectiveEventCount, in: previous),
                unit: "회/일",
                improvedMessage: "방해 앱 체류 신호가 줄었어요.",
                declinedMessage: "방해 앱 체류 신호가 늘었어요.",
                steadyMessage: "방해 앱 체류는 지난 주와 비슷해요."
            ),
            lowerIsBetterMetric(
                title: "복귀 지연",
                current: average(\.returnEventCount, in: current),
                previous: average(\.returnEventCount, in: previous),
                unit: "회/일",
                improvedMessage: "휴식 후 복귀 지연이 줄었어요.",
                declinedMessage: "휴식 후 복귀 지연이 늘었어요.",
                steadyMessage: "복귀 지연은 지난 주와 비슷해요."
            ),
            lowerIsBetterMetric(
                title: "조기 중단",
                current: average(\.sustainedEventCount, in: current),
                previous: average(\.sustainedEventCount, in: previous),
                unit: "회/일",
                improvedMessage: "목표 시간보다 일찍 멈춘 세션이 줄었어요.",
                declinedMessage: "목표 시간보다 일찍 멈춘 세션이 늘었어요.",
                steadyMessage: "조기 중단은 지난 주와 비슷해요."
            ),
        ]

        return WeeklyAttentionTrendReport(
            currentDayCount: current.count,
            previousDayCount: previous.count,
            metrics: metrics,
            summaryMessage: summaryMessage(metrics),
            guidanceMessage: guidanceMessage(metrics)
        )
    }

    private static var emptyReport: WeeklyAttentionTrendReport {
        WeeklyAttentionTrendReport(
            currentDayCount: 0,
            previousDayCount: 0,
            metrics: [],
            summaryMessage: "비교할 수 있는 주간 기록이 아직 없어요.",
            guidanceMessage: "며칠 더 기록이 쌓이면 전보다 나아진 점과 흔들린 점을 비교해볼 수 있어요."
        )
    }

    private static func higherIsBetterMetric(
        title: String,
        current: Double,
        previous: Double,
        unit: String,
        improvedMessage: String,
        declinedMessage: String,
        steadyMessage: String
    ) -> AttentionTrendMetric {
        makeMetric(
            title: title,
            current: current,
            previous: previous,
            unit: unit,
            isImproved: current > previous,
            changeMagnitude: abs(current - previous),
            improvedMessage: improvedMessage,
            declinedMessage: declinedMessage,
            steadyMessage: steadyMessage
        )
    }

    private static func lowerIsBetterMetric(
        title: String,
        current: Double,
        previous: Double,
        unit: String,
        improvedMessage: String,
        declinedMessage: String,
        steadyMessage: String
    ) -> AttentionTrendMetric {
        makeMetric(
            title: title,
            current: current,
            previous: previous,
            unit: unit,
            isImproved: current < previous,
            changeMagnitude: abs(current - previous),
            improvedMessage: improvedMessage,
            declinedMessage: declinedMessage,
            steadyMessage: steadyMessage
        )
    }

    private static func makeMetric(
        title: String,
        current: Double,
        previous: Double,
        unit: String,
        isImproved: Bool,
        changeMagnitude: Double,
        improvedMessage: String,
        declinedMessage: String,
        steadyMessage: String
    ) -> AttentionTrendMetric {
        let threshold = unit == "점" ? 4.0 : 0.15
        let direction: AttentionTrendDirection
        let message: String
        if changeMagnitude < threshold {
            direction = .steady
            message = steadyMessage
        } else if isImproved {
            direction = .improved
            message = improvedMessage
        } else {
            direction = .declined
            message = declinedMessage
        }

        return AttentionTrendMetric(
            title: title,
            currentValueText: format(current, unit: unit),
            previousValueText: format(previous, unit: unit),
            direction: direction,
            message: message
        )
    }

    private static func averageScore(_ summaries: [AttentionDaySummary]) -> Double {
        guard !summaries.isEmpty else { return 0 }
        let total = summaries.reduce(0.0) { $0 + $1.overallScore }
        return total / Double(summaries.count) * 100
    }

    private static func average(
        _ keyPath: KeyPath<AttentionDaySummary, Int>,
        in summaries: [AttentionDaySummary]
    ) -> Double {
        guard !summaries.isEmpty else { return 0 }
        let total = summaries.reduce(0) { $0 + $1[keyPath: keyPath] }
        return Double(total) / Double(summaries.count)
    }

    private static func summaryMessage(_ metrics: [AttentionTrendMetric]) -> String {
        let improved = metrics.filter { $0.direction == .improved }
        let declined = metrics.filter { $0.direction == .declined }
        if improved.count > declined.count {
            return "지난 주보다 좋아진 신호가 더 많아요."
        }
        if declined.count > improved.count {
            return "지난 주보다 흔들린 신호가 더 많아요."
        }
        return "지난 주와 비슷한 흐름을 유지하고 있어요."
    }

    private static func guidanceMessage(_ metrics: [AttentionTrendMetric]) -> String {
        if metrics.contains(where: { $0.title == "복귀 지연" && $0.direction == .declined }) {
            return "이번 주는 휴식 후 복귀가 핵심이에요. 휴식 전에 돌아올 작업 화면을 미리 열어두세요."
        }
        if metrics.contains(where: { $0.title == "방해 앱 체류" && $0.direction == .declined }) {
            return "메시지/엔터 앱 체류가 늘고 있어요. 포모도로 중 확인할 앱을 세션 사이로 제한해보세요."
        }
        if metrics.contains(where: { $0.title == "조기 중단" && $0.direction == .declined }) {
            return "완료율이 떨어지는 흐름이에요. 다음 주는 집중 시간을 5~10분 짧게 잡는 편이 나아요."
        }
        if metrics.contains(where: { $0.direction == .improved }) {
            return "좋아진 흐름이 있어요. 이번 주에 잘 된 시간대와 집중 타이머 1회 길이를 다음 주에도 유지해보세요."
        }
        return "큰 변화는 없어요. 우선 같은 시간대에 첫 집중 세션을 고정해 리듬을 더 선명하게 만들어보세요."
    }

    private static func format(_ value: Double, unit: String) -> String {
        if unit == "점" {
            return "\(Int(round(value)))점"
        }
        return String(format: "%.1f%@", value, unit)
    }
}

enum DailyAttentionReportBuilder {
    private struct SegmentSlice {
        let start: Date
        let end: Date
        let category: String
    }

    private struct FocusRun {
        let start: Date
        let end: Date
        let categoryDurations: [String: Int]
        let switches: Int

        var durationSeconds: Int {
            max(0, Int(end.timeIntervalSince(start)))
        }

        var primaryCategory: String? {
            categoryDurations.max { $0.value < $1.value }?.key
        }
    }

    static func build(
        day: Date,
        buckets: [TimelineBucket],
        segments: [AppUsageSegment],
        timerSessions: [FocusSession],
        attentionSummary: AttentionSummary,
        thresholds: AttentionThresholds = .standard,
        isFinalized: Bool
    ) -> DailyAttentionReport {
        let visibleBuckets = buckets.filter { $0.totalSeconds >= 5 * 60 }
        let scoredBuckets = visibleBuckets.map { bucket in
            (bucket, score(bucket, attentionEvents: attentionSummary.events))
        }

        let bucketBest = scoredBuckets
            .max { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                return lhs.0.totalSeconds < rhs.0.totalSeconds
            }
            .map { makeWindow(kind: .best, bucket: $0.0, score: $0.1) }

        let bucketWorst = scoredBuckets
            .min { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                return lhs.0.switches > rhs.0.switches
            }
            .map { makeWindow(kind: .worst, bucket: $0.0, score: $0.1) }

        let best = isFinalized
            ? (longestFullDayWindow(day: day, segments: segments, timerSessions: timerSessions) ?? bucketBest)
            : bucketBest

        let worst = isFinalized
            ? fullDayWorstWindow(
                day: day,
                segments: segments,
                buckets: buckets,
                attentionEvents: attentionSummary.events,
                fallback: bucketWorst
            )
            : bucketWorst

        let quickRecovery = quickRecoveryMoment(
            segments: segments,
            timerSessions: timerSessions,
            thresholds: thresholds
        )
        let difficultRecovery = difficultRecoveryMoment(from: attentionSummary)
        let flowState = attentionSummary.hasSignals ? attentionSummary.flowState : inferredFlowState(from: best)

        return DailyAttentionReport(
            day: day,
            isFinalized: isFinalized,
            flowState: flowState,
            bestWindow: best,
            worstWindow: worst,
            quickRecovery: quickRecovery,
            difficultRecovery: difficultRecovery,
            patternMessage: patternMessage(
                best: best,
                worst: worst,
                attentionSummary: attentionSummary,
                isFinalized: isFinalized
            ),
            guidanceMessage: guidanceMessage(
                best: best,
                worst: worst,
                attentionSummary: attentionSummary,
                quickRecovery: quickRecovery,
                difficultRecovery: difficultRecovery
            )
        )
    }

    private static func longestFullDayWindow(
        day: Date,
        segments: [AppUsageSegment],
        timerSessions: [FocusSession]
    ) -> DailyAttentionWindow? {
        guard let run = focusRuns(day: day, segments: segments, timerSessions: timerSessions)
            .max(by: { lhs, rhs in
                if lhs.durationSeconds != rhs.durationSeconds {
                    return lhs.durationSeconds < rhs.durationSeconds
                }
                return lhs.switches > rhs.switches
            }),
            run.durationSeconds >= 5 * 60
        else {
            return nil
        }

        let category = run.primaryCategory ?? "한 작업"
        let reason: String
        if run.switches == 0 {
            reason = "\(category) 흐름이 전환 없이 \(durationText(run.durationSeconds)) 이어졌어요."
        } else {
            reason = "\(category) 중심 흐름이 \(durationText(run.durationSeconds)) 이어졌고, 전환 \(run.switches)회가 섞였어요."
        }

        return DailyAttentionWindow(
            kind: .best,
            start: run.start,
            end: run.end,
            primaryCategory: run.primaryCategory,
            score: 1,
            durationSeconds: run.durationSeconds,
            switches: run.switches,
            reason: reason
        )
    }

    private static func focusRuns(
        day: Date,
        segments: [AppUsageSegment],
        timerSessions: [FocusSession]
    ) -> [FocusRun] {
        let slices = clippedSegments(day: day, segments: segments)
        guard !slices.isEmpty else { return [] }

        let maxGap: TimeInterval = 120
        var runs: [FocusRun] = []
        var runStart = slices[0].start
        var runEnd = slices[0].end
        var previous = slices[0]
        var categoryDurations: [String: Int] = [
            slices[0].category: Int(slices[0].end.timeIntervalSince(slices[0].start))
        ]
        var switches = 0

        for slice in slices.dropFirst() {
            let gap = slice.start.timeIntervalSince(previous.end)
            let continues = gap <= maxGap && isSameFocusFlow(previous, slice, timerSessions: timerSessions)
            if continues {
                if previous.category != slice.category && !isExemptSwitch(previous, slice, timerSessions: timerSessions) {
                    switches += 1
                }
                runEnd = max(runEnd, slice.end)
                categoryDurations[slice.category, default: 0] += Int(slice.end.timeIntervalSince(slice.start))
            } else {
                runs.append(FocusRun(start: runStart, end: runEnd, categoryDurations: categoryDurations, switches: switches))
                runStart = slice.start
                runEnd = slice.end
                categoryDurations = [slice.category: Int(slice.end.timeIntervalSince(slice.start))]
                switches = 0
            }
            previous = slice
        }

        runs.append(FocusRun(start: runStart, end: runEnd, categoryDurations: categoryDurations, switches: switches))
        return runs
    }

    private static func isSameFocusFlow(
        _ previous: SegmentSlice,
        _ current: SegmentSlice,
        timerSessions: [FocusSession]
    ) -> Bool {
        previous.category == current.category || isExemptSwitch(previous, current, timerSessions: timerSessions)
    }

    private static func isExemptSwitch(
        _ previous: SegmentSlice,
        _ current: SegmentSlice,
        timerSessions: [FocusSession]
    ) -> Bool {
        CategoryPairStore.shared.contains(previous.category, current.category)
            || TimelineAnalytics.isInTimerSession(current.start, sessions: timerSessions)
    }

    private static func clippedSegments(
        day: Date,
        segments: [AppUsageSegment]
    ) -> [SegmentSlice] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }

        return segments.compactMap { segment in
            guard !Constants.hiddenLegacyCategories.contains(segment.category) else { return nil }
            let start = max(segment.startTime, dayStart)
            let end = min(segment.endTime, dayEnd)
            guard end > start else { return nil }
            return SegmentSlice(start: start, end: end, category: segment.category)
        }
        .sorted { $0.start < $1.start }
    }

    private static func fullDayWorstWindow(
        day: Date,
        segments: [AppUsageSegment],
        buckets: [TimelineBucket],
        attentionEvents: [AttentionEventCandidate],
        fallback: DailyAttentionWindow?
    ) -> DailyAttentionWindow? {
        let problemEvents = attentionEvents.filter { $0.type != .allowedSwitch }
        guard !problemEvents.isEmpty else {
            return fallback
        }

        let windowSeconds: TimeInterval = 30 * 60
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(24 * 60 * 60)
        let candidates = problemEvents.map { event -> (start: Date, end: Date, events: [AttentionEventCandidate]) in
            let start = max(dayStart, event.occurredAt)
            let end = min(dayEnd, start.addingTimeInterval(windowSeconds))
            let events = problemEvents.filter { $0.occurredAt >= start && $0.occurredAt < end }
            return (start, end, events)
        }

        guard let selected = candidates.max(by: { lhs, rhs in
            let lhsDuration = lhs.events.reduce(0) { $0 + $1.durationSeconds }
            let rhsDuration = rhs.events.reduce(0) { $0 + $1.durationSeconds }
            if lhs.events.count != rhs.events.count {
                return lhs.events.count < rhs.events.count
            }
            return lhsDuration < rhsDuration
        }) else {
            return fallback
        }

        let overlapped = clippedSegments(day: day, segments: segments).filter {
            $0.end > selected.start && $0.start < selected.end
        }
        let categoryDurations = overlapped.reduce(into: [String: Int]()) { result, slice in
            let start = max(slice.start, selected.start)
            let end = min(slice.end, selected.end)
            result[slice.category, default: 0] += max(0, Int(end.timeIntervalSince(start)))
        }
        let primary = categoryDurations.max { $0.value < $1.value }?.key
        let eventSummary = eventReason(selected.events, primaryCategory: primary)
        let switchCount = buckets
            .filter { $0.endTime > selected.start && $0.startTime < selected.end }
            .reduce(0) { $0 + $1.switches }

        return DailyAttentionWindow(
            kind: .worst,
            start: selected.start,
            end: selected.end,
            primaryCategory: primary,
            score: 0,
            durationSeconds: Int(selected.end.timeIntervalSince(selected.start)),
            switches: switchCount,
            reason: eventSummary
        )
    }

    private static func eventReason(_ events: [AttentionEventCandidate], primaryCategory: String?) -> String {
        let selective = events.filter { $0.type == .selectiveDistraction }.count
        let sustained = events.filter { $0.type == .sustainedDrop }.count
        let delayed = events.filter { $0.type == .delayedReturn }.count
        let context = primaryCategory.map { "\($0) 흐름에서 " } ?? ""
        let activeTypes = [selective, sustained, delayed].filter { $0 > 0 }.count

        if activeTypes == 1 {
            if selective > 0 {
                return "\(context)방해 가능 앱에 머문 신호가 보였어요."
            }
            if sustained > 0 {
                return "\(context)집중 타이머가 목표보다 일찍 끝났어요."
            }
            if delayed > 0 {
                return "\(context)휴식 뒤 원래 흐름으로 돌아오는 데 시간이 걸렸어요."
            }
        }

        var parts: [String] = []
        if selective > 0 { parts.append("방해 앱 체류 \(selective)회") }
        if sustained > 0 { parts.append("조기 중단 \(sustained)회") }
        if delayed > 0 { parts.append("복귀 지연 \(delayed)회") }
        guard !parts.isEmpty else {
            return "\(context)주의 흐름이 가장 많이 흔들렸어요."
        }
        return "\(context)\(parts.joined(separator: ", ")) 신호가 함께 보였어요."
    }

    private static func score(
        _ bucket: TimelineBucket,
        attentionEvents: [AttentionEventCandidate]
    ) -> Double {
        let activityRatio = min(1, Double(bucket.totalSeconds) / max(1, bucket.endTime.timeIntervalSince(bucket.startTime)))
        let eventPenalty = attentionEvents.reduce(0.0) { total, event in
            guard event.type != .allowedSwitch else { return total }
            guard event.occurredAt >= bucket.startTime && event.occurredAt < bucket.endTime else { return total }
            switch event.type {
            case .selectiveDistraction:
                return total + 0.22
            case .sustainedDrop:
                return total + 0.18
            case .delayedReturn:
                return total + 0.25
            case .allowedSwitch:
                return total
            }
        }
        return min(1, max(0, bucket.focusScore * activityRatio - eventPenalty))
    }

    private static func makeWindow(
        kind: DailyAttentionWindow.Kind,
        bucket: TimelineBucket,
        score: Double
    ) -> DailyAttentionWindow {
        let primary = bucket.sortedCategories.first
        let reason: String
        switch kind {
        case .best:
            if bucket.switches == 0 {
                reason = "전환 없이 \(durationText(bucket.totalSeconds)) 이어졌어요."
            } else {
                reason = "전환 \(bucket.switches)회 안에서 \(primary?.category ?? "한 작업") 흐름이 가장 오래 유지됐어요."
            }
        case .worst:
            if bucket.switches >= 3 {
                reason = "이 구간에서 작업 전환이 \(bucket.switches)회 발생해 흐름이 가장 자주 끊겼어요."
            } else {
                reason = "\(primary?.category ?? "여러 작업")에 머문 시간이 짧게 끊겼어요."
            }
        }

        return DailyAttentionWindow(
            kind: kind,
            start: bucket.startTime,
            end: bucket.endTime,
            primaryCategory: primary?.category,
            score: score,
            durationSeconds: bucket.totalSeconds,
            switches: bucket.switches,
            reason: reason
        )
    }

    private static func quickRecoveryMoment(
        segments: [AppUsageSegment],
        timerSessions: [FocusSession],
        thresholds: AttentionThresholds
    ) -> DailyRecoveryMoment? {
        let sortedSegments = segments.sorted { $0.startTime < $1.startTime }
        var moments: [DailyRecoveryMoment] = []

        for session in timerSessions where session.completed {
            guard let endedAt = session.endedAt else { continue }
            let targetCategory = session.category ?? Constants.defaultFocusCategory
            let expectedReturnAt = endedAt.addingTimeInterval(TimeInterval(max(0, session.breakMinutes * 60)))
            guard let returnSegment = sortedSegments.first(where: {
                $0.endTime > expectedReturnAt && ($0.category == targetCategory || CategoryPairStore.shared.contains($0.category, targetCategory))
            }) else {
                continue
            }
            let delay = max(0, Int(returnSegment.startTime.timeIntervalSince(expectedReturnAt)))
            guard TimeInterval(delay) < thresholds.returnDelaySeconds else { continue }

            moments.append(DailyRecoveryMoment(
                kind: .quickReturn,
                occurredAt: expectedReturnAt,
                durationSeconds: delay,
                category: targetCategory,
                message: "휴식 후 \(durationText(delay)) 만에 \(targetCategory) 흐름으로 돌아왔어요."
            ))
        }

        return moments.min { $0.durationSeconds < $1.durationSeconds }
    }

    private static func difficultRecoveryMoment(
        from summary: AttentionSummary
    ) -> DailyRecoveryMoment? {
        summary.events
            .filter { $0.type == .delayedReturn }
            .max { $0.durationSeconds < $1.durationSeconds }
            .map {
                DailyRecoveryMoment(
                    kind: .delayedReturn,
                    occurredAt: $0.occurredAt,
                    durationSeconds: $0.durationSeconds,
                    category: $0.targetCategory,
                    message: "휴식 후 복귀가 \(durationText($0.durationSeconds)) 늦어졌어요."
                )
            }
    }

    private static func inferredFlowState(from best: DailyAttentionWindow?) -> AttentionFlowState {
        guard let best else { return .noRecord }
        if best.score >= 0.70 { return .steady }
        if best.score >= 0.45 { return .variable }
        return .returnNeeded
    }

    private static func patternMessage(
        best: DailyAttentionWindow?,
        worst: DailyAttentionWindow?,
        attentionSummary: AttentionSummary,
        isFinalized: Bool
    ) -> String {
        let prefix = isFinalized ? "이 날은" : "오늘은 지금까지"
        let selectiveCount = attentionSummary.events.filter { $0.type == .selectiveDistraction }.count
        let returnCount = attentionSummary.events.filter { $0.type == .delayedReturn }.count
        let sustainedCount = attentionSummary.events.filter { $0.type == .sustainedDrop }.count

        if let best, let worst {
            if returnCount > 0 {
                return "\(prefix) \(timeOfDayLabel(best.start)) 흐름은 좋았고, 휴식 후 복귀가 가장 큰 변수였어요."
            }
            if selectiveCount > 0 {
                return "\(prefix) \(timeOfDayLabel(best.start))에 가장 잘 머물렀고, \(timeOfDayLabel(worst.start))에는 방해 앱 체류가 섞였어요."
            }
            if sustainedCount > 0 {
                return "\(prefix) 몰입 구간은 있었지만 목표 시간보다 일찍 멈춘 세션이 있었어요."
            }
            return "\(prefix) \(timeOfDayLabel(best.start))에 가장 안정적인 흐름이 보였어요."
        }

        return isFinalized ? "이 날은 회고할 만큼의 세부 타임라인이 부족해요." : "오늘은 아직 회고할 만큼의 세부 타임라인이 부족해요."
    }

    private static func guidanceMessage(
        best: DailyAttentionWindow?,
        worst: DailyAttentionWindow?,
        attentionSummary: AttentionSummary,
        quickRecovery: DailyRecoveryMoment?,
        difficultRecovery: DailyRecoveryMoment?
    ) -> String {
        let selectiveCount = attentionSummary.events.filter { $0.type == .selectiveDistraction }.count
        let sustainedCount = attentionSummary.events.filter { $0.type == .sustainedDrop }.count
        let returnCount = attentionSummary.events.filter { $0.type == .delayedReturn }.count

        if returnCount > 0 || difficultRecovery != nil {
            return "휴식 전에 돌아올 작업 화면을 열어두고, 휴식 타이머를 짧게 고정해보세요."
        }
        if selectiveCount >= 2 {
            return "메시지나 엔터 앱 확인은 포모도로 사이로 미루는 규칙이 잘 맞을 가능성이 높아요."
        }
        if sustainedCount > 0 {
            return "목표 시간을 줄여도 괜찮아요. 당장은 짧은 세션을 끝까지 완료하는 쪽이 더 안정적입니다."
        }
        if let best {
            return "\(timeOfDayLabel(best.start))에 중요한 작업을 배치하면 오늘 패턴과 잘 맞아요."
        }
        if quickRecovery != nil {
            return "휴식 후 복귀 흐름이 좋았어요. 같은 휴식 길이를 유지해보세요."
        }
        return "기록이 조금 더 쌓이면 시간대별 맞춤 가이드를 보여줄 수 있어요."
    }

    private static func timeOfDayLabel(_ date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<12:
            return "오전"
        case 12..<17:
            return "오후"
        case 17..<22:
            return "저녁"
        default:
            return "늦은 시간"
        }
    }

    private static func durationText(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)초"
        }
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        if remainingSeconds == 0 {
            return "\(minutes)분"
        }
        return "\(minutes)분 \(remainingSeconds)초"
    }
}
