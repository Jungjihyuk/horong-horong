import Foundation
import SwiftData

/// 몰입도를 저장소에서 읽어오는 유일한 경계.
///
/// 과거 그래프와 진행 중 세션이 **반드시 같은 `observation(...)` 과 `score(_:category:)` 를 지난다.**
/// 그래야 완료 세션 그래프와 개인화·실시간 판정이 서로 다른 계산법으로 어긋나지 않는다.
enum FocusScoreHistory {
    static let dayCount = 14
    static let nudgeWindowSeconds: TimeInterval = 10 * 60
    private static let personalizationWindowStepSeconds: TimeInterval = 60

    private struct SessionWindow {
        let session: FocusSession
        let intervals: [DateInterval]

        var start: Date { intervals.first?.start ?? session.startedAt }
        var end: Date { intervals.last?.end ?? session.startedAt }
    }

    /// 지난 N일의 완료된 포모도로 세션별 몰입도. 시간순.
    static func samples(
        days: Int = dayCount,
        now: Date = Date(),
        modelContext: ModelContext
    ) -> [FocusScoreSample] {
        guard let periodStart = Calendar.current.date(byAdding: .day, value: -days, to: now) else {
            return []
        }

        // 경계에 걸친 세션을 놓치지 않도록 세션 조회만 앞으로 당긴다. (AttentionAnalytics 와 같은 관례)
        let bufferStart = periodStart.addingTimeInterval(-4 * 3600)
        let sessions = (try? modelContext.fetch(
            FetchDescriptor<FocusSession>(
                predicate: #Predicate { $0.startedAt >= bufferStart && $0.startedAt < now },
                sortBy: [SortDescriptor(\.startedAt)]
            )
        )) ?? []

        let windows = sessions.compactMap { session -> SessionWindow? in
            guard isCompletedPomodoro(session) else { return nil }
            let intervals = focusIntervals(for: session)
            guard let end = intervals.last?.end, end > periodStart else { return nil }
            return SessionWindow(session: session, intervals: intervals)
        }
        guard let firstStart = windows.map(\.start).min(),
              let lastEnd = windows.map(\.end).max() else {
            return []
        }

        let segments = (try? modelContext.fetch(
            FetchDescriptor<AppUsageSegment>(
                predicate: #Predicate { $0.startTime < lastEnd && $0.endTime > firstStart },
                sortBy: [SortDescriptor(\.startTime)]
            )
        )) ?? []

        // 세션과 세그먼트 모두 시간순이라 커서를 전진시키며 훑는다.
        // 세션마다 전체를 다시 훑으면 14일치에서 수십만 번 비교가 된다.
        var cursor = 0
        return windows.map { window in
            while cursor < segments.count, segments[cursor].endTime <= window.start {
                cursor += 1
            }
            var index = cursor
            var overlapping: [AppUsageSegment] = []
            while index < segments.count, segments[index].startTime < window.end {
                if segments[index].endTime > window.start {
                    overlapping.append(segments[index])
                }
                index += 1
            }

            let category = window.session.category ?? Constants.defaultFocusCategory
            let analysis = analyze(
                intervals: window.intervals,
                segments: overlapping,
                category: category
            )
            return FocusScoreSample(
                id: window.session.id,
                startedAt: window.session.startedAt,
                category: category,
                score: analysis.score,
                categorySeconds: analysis.categorySeconds
            )
        }
    }

    /// 진행 중 세션의 최근 활동 10분. 일시정지는 창의 시간에도, 점수에도 들어가지 않는다.
    static func liveWindowMetrics(
        activeIntervals: [DateInterval],
        focusCategory: String,
        modelContext: ModelContext
    ) -> FocusNudgeWindowMetrics? {
        let intervals = trailingIntervals(
            from: activeIntervals,
            duration: nudgeWindowSeconds
        )
        guard let windowStart = intervals.first?.start,
              let windowEnd = intervals.last?.end else { return nil }
        let segments = (try? modelContext.fetch(
            FetchDescriptor<AppUsageSegment>(
                predicate: #Predicate { $0.startTime < windowEnd && $0.endTime > windowStart },
                sortBy: [SortDescriptor(\.startTime)]
            )
        )) ?? []
        return windowMetrics(
            intervals: intervals,
            segments: segments,
            focusCategory: focusCategory
        )
    }

    /// 완료 세션 안의 최근 10분 창을 활동 시간 1분 간격으로 만든다.
    /// 개인화도 실시간과 같은 창을 학습해야 경계의 의미가 달라지지 않는다.
    static func sessionWindowMetrics(
        activeIntervals: [DateInterval],
        segments: [AppUsageSegment],
        focusCategory: String
    ) -> [FocusNudgeWindowMetrics] {
        let sorted = activeIntervals.filter { $0.duration > 0 }.sorted { $0.start < $1.start }
        let total = sorted.reduce(0) { $0 + $1.duration }
        guard total >= nudgeWindowSeconds else { return [] }

        var endpoints: [TimeInterval] = []
        var endpoint = nudgeWindowSeconds
        while endpoint <= total {
            endpoints.append(endpoint)
            endpoint += personalizationWindowStepSeconds
        }
        if endpoints.last.map({ total - $0 >= 1 }) ?? true {
            endpoints.append(total)
        }

        return endpoints.compactMap { activeSeconds in
            let prefix = prefixIntervals(from: sorted, duration: activeSeconds)
            let window = trailingIntervals(from: prefix, duration: nudgeWindowSeconds)
            return windowMetrics(
                intervals: window,
                segments: segments,
                focusCategory: focusCategory
            )
        }
    }

    private static func windowMetrics(
        intervals: [DateInterval],
        segments: [AppUsageSegment],
        focusCategory: String
    ) -> FocusNudgeWindowMetrics? {
        let duration = intervals.reduce(0) { $0 + $1.duration }
        guard duration >= nudgeWindowSeconds - 0.5 else { return nil }
        let analysis = analyze(
            intervals: intervals,
            segments: segments,
            category: focusCategory
        )
        return FocusNudgeWindowMetrics(
            score: analysis.score,
            appSwitchCount: analysis.appSwitchCount
        )
    }

    private static func trailingIntervals(
        from intervals: [DateInterval],
        duration: TimeInterval
    ) -> [DateInterval] {
        var remaining = max(0, duration)
        var result: [DateInterval] = []
        for interval in intervals.filter({ $0.duration > 0 }).sorted(by: { $0.start < $1.start }).reversed() {
            guard remaining > 0 else { break }
            let taken = min(interval.duration, remaining)
            result.append(
                DateInterval(
                    start: interval.end.addingTimeInterval(-taken),
                    end: interval.end
                )
            )
            remaining -= taken
        }
        guard remaining <= 0.5 else { return [] }
        return Array(result.reversed())
    }

    private static func prefixIntervals(
        from intervals: [DateInterval],
        duration: TimeInterval
    ) -> [DateInterval] {
        var remaining = max(0, duration)
        var result: [DateInterval] = []
        for interval in intervals where interval.duration > 0 {
            guard remaining > 0 else { break }
            let taken = min(interval.duration, remaining)
            result.append(
                DateInterval(
                    start: interval.start,
                    end: interval.start.addingTimeInterval(taken)
                )
            )
            remaining -= taken
        }
        return result
    }

    /// 여러 집중 구간을 각각 관측한 뒤 합친다. 구간 사이의 일시정지는 분자·분모 모두에 들어오지 않는다.
    private static func analyze(
        intervals: [DateInterval],
        segments: [AppUsageSegment],
        category: String
    ) -> (score: FocusScore, categorySeconds: [String: Int], appSwitchCount: Int) {
        var focusSeconds = 0
        var measuredSeconds = 0
        var totalSeconds = 0
        var classifiedAppSeconds = 0
        var recordedAppSeconds = 0
        var appSwitchCount = 0
        var categorySeconds: [String: Int] = [:]

        for interval in intervals where interval.duration > 0 {
            let observation = observation(
                start: interval.start,
                end: interval.end,
                segments: segments
            )
            let intervalScore = score(observation, category: category)
            focusSeconds += intervalScore.focusSeconds
            measuredSeconds += intervalScore.measuredSeconds
            totalSeconds += intervalScore.totalSeconds
            classifiedAppSeconds += intervalScore.classifiedAppSeconds
            recordedAppSeconds += intervalScore.recordedAppSeconds
            appSwitchCount += max(0, observation.appSwitchCount)
            for entry in observation.categories {
                categorySeconds[entry.category, default: 0] += max(0, entry.durationSeconds)
            }
        }

        return (
            FocusScore(
                focusSeconds: focusSeconds,
                measuredSeconds: measuredSeconds,
                totalSeconds: totalSeconds,
                classifiedAppSeconds: classifiedAppSeconds,
                recordedAppSeconds: recordedAppSeconds
            ),
            categorySeconds,
            appSwitchCount
        )
    }

    /// 세션 창의 관측. 과거와 실시간이 같은 창 정의를 쓰게 하는 지점.
    private static func observation(
        start: Date,
        end: Date,
        segments: [AppUsageSegment]
    ) -> PomodoroSessionObservation {
        PomodoroSessionObservationBuilder.observation(from: start, to: end, segments: segments)
    }

    /// 과거와 실시간이 함께 지나는 단 하나의 계산.
    /// 짝 판정이 여기 한 곳에만 있어야 두 화면의 숫자가 갈라지지 않는다.
    private static func score(
        _ observation: PomodoroSessionObservation,
        category: String
    ) -> FocusScore {
        FocusScoreCalculator.score(
            observation: observation,
            focusCategory: category,
            isPaired: { CategoryPairStore.shared.contains($0, $1) }
        )
    }

    /// 통계 화면과 같은 기준으로 "끝난 포모도로" 를 가린다. (`StatsAggregateCache` 와 동일)
    static func isCompletedPomodoro(_ session: FocusSession) -> Bool {
        guard let endedAt = session.endedAt else { return false }
        let expectedSeconds = max(0, session.focusMinutes) * 60
        guard expectedSeconds > 0 else { return false }
        return session.completed
            || endedAt.timeIntervalSince(session.startedAt) >= TimeInterval(expectedSeconds)
    }

    /// 새 세션은 실제 집중 구간을 쓰고, 구간 기록이 없는 과거 세션은 기존 단일 창 계산을 유지한다.
    static func focusIntervals(for session: FocusSession) -> [DateInterval] {
        guard let endedAt = session.endedAt else { return [] }
        if session.hasPauseIntervalTracking {
            return FocusSessionActivityIntervals.make(
                startedAt: session.startedAt,
                endedAt: endedAt,
                excluding: session.pauseIntervals,
                maximumActiveSeconds: TimeInterval(session.recordedFocusSeconds)
            )
        }

        let expectedEnd = session.startedAt.addingTimeInterval(
            TimeInterval(max(0, session.focusMinutes) * 60)
        )
        let end = min(endedAt, expectedEnd)
        guard end > session.startedAt else { return [] }
        return [DateInterval(start: session.startedAt, end: end)]
    }
}
