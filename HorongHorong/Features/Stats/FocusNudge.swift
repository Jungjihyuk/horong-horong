import Foundation
import SwiftData

// MARK: - 판정 입력

struct FocusReflectionSummary: Equatable, Sendable {
    static let minimumComparableResponseCount = 3
    static let maximumComparableResponseCountGap = 2
    static let meaningfulFocusedResponseDelta = 2
    static let empty = FocusReflectionSummary(
        focusedResponseCount: 0,
        validResponseCount: 0
    )

    let focusedResponseCount: Int
    let validResponseCount: Int

    func focusedResponseDelta(
        comparedTo previous: FocusReflectionSummary
    ) -> Int? {
        guard validResponseCount >= Self.minimumComparableResponseCount,
              previous.validResponseCount >= Self.minimumComparableResponseCount,
              abs(validResponseCount - previous.validResponseCount)
                <= Self.maximumComparableResponseCountGap else {
            return nil
        }
        return focusedResponseCount - previous.focusedResponseCount
    }
}

/// 넛지 판정에 쓰는 값 스냅샷. SwiftData 모델을 들고 있지 않으므로 테스트에서 그대로 만들어 쓸 수 있다.
struct FocusNudgeContext: Sendable {
    struct TaskCandidate: Equatable, Sendable {
        let title: String
        /// 시작일 또는 마감 시각. 시각 정보가 없으면 nil.
        let at: Date?
        /// 마감이 이미 지난 할 일.
        let isOverdue: Bool
    }

    let day: Date
    let now: Date

    /// 오늘 완료한 포모도로 수와 그 합계 시간.
    let todayCompletedCount: Int
    let todayFocusSeconds: Int
    /// 어제 같은 시각까지의 완료 수. 오늘 진행 속도를 비교할 기준선.
    let yesterdayCountBySameTime: Int
    let yesterdayCompletedCount: Int

    /// 최근 7일과 그 이전 7일의 유효 회고 및 '깊게/대체로 집중' 응답 횟수.
    let recentReflection: FocusReflectionSummary
    let previousReflection: FocusReflectionSummary
    /// 최근 7일에서 가장 오래 몰입한 카테고리.
    let topCategory: String?
    /// 최근 7일에서 가장 자주 고른 미완료 이유.
    let topIncompleteReason: PomodoroIncompleteReason?
    let topIncompleteReasonCount: Int

    /// 오늘 앱 관찰로 기록된 총 시간(중복 제거)과 그중 타이머 안에서 보낸 시간.
    let observedSeconds: Int
    let coveredSeconds: Int

    /// 오늘 예정된 할 일(메모) 집계. 마감이 지난 이전 날짜의 할 일은 포함하지 않는다.
    let openTaskCount: Int
    let totalTaskCount: Int
    /// 오늘을 포함해 현재 시각까지 마감이 지났지만 완료하지 않은 할 일.
    let overdueTaskCount: Int
    let nextTask: TaskCandidate?

    /// 오늘 이전 14일 중 포모도로를 한 번이라도 완료한 날 수. 콜드스타트 판정 기준.
    let recordedDayCount: Int
}

extension FocusNudgeContext {
    /// 과거 포모도로 기록이 없고 오늘도 아직 시작하지 않은 상태.
    var isColdStart: Bool {
        recordedDayCount == 0 && todayCompletedCount == 0
    }

    /// 오늘 기록된 시간 중 타이머 안에서 보낸 비율. 표본이 30분 미만이면 판단하지 않는다.
    var coverageRatio: Double? {
        guard observedSeconds >= 30 * 60 else { return nil }
        return Double(coveredSeconds) / Double(observedSeconds)
    }

    /// 두 기간의 전체 회고 수가 비슷하고 각각 3개 이상일 때의 몰입 응답 횟수 변화.
    var focusedResponseDelta: Int? {
        recentReflection.focusedResponseDelta(comparedTo: previousReflection)
    }

    static func empty(day: Date, now: Date) -> FocusNudgeContext {
        FocusNudgeContext(
            day: day,
            now: now,
            todayCompletedCount: 0,
            todayFocusSeconds: 0,
            yesterdayCountBySameTime: 0,
            yesterdayCompletedCount: 0,
            recentReflection: .empty,
            previousReflection: .empty,
            topCategory: nil,
            topIncompleteReason: nil,
            topIncompleteReasonCount: 0,
            observedSeconds: 0,
            coveredSeconds: 0,
            openTaskCount: 0,
            totalTaskCount: 0,
            overdueTaskCount: 0,
            nextTask: nil,
            recordedDayCount: 0
        )
    }
}

// MARK: - 판정 결과

struct FocusNudge: Sendable {
    enum Tier: Sendable {
        /// 이용 내역이 없는 사용자에게 보여주는 시작 유도.
        case coldStart
        /// 오늘 진행 상황을 기준선과 비교해 알려주는 문구.
        case today
        /// 최근 데이터에서 읽어낸 패턴·추세.
        case personalized
    }

    let ruleID: String
    let tier: Tier
    /// 캡슐에 들어가는 짧은 라벨.
    let badge: String
    /// 본문 한 문장.
    let message: String
}

/// 하나의 문구 전략. 조건과 문구만 담고 있어 카탈로그에서 자유롭게 넣고 뺄 수 있다.
struct FocusNudgeRule: Sendable {
    let id: String
    let tier: FocusNudge.Tier
    /// 클수록 먼저 선택된다. 같은 값이면 카탈로그에 먼저 적은 규칙이 이긴다.
    let priority: Int
    let badge: String
    let condition: @Sendable (FocusNudgeContext) -> Bool
    /// 여러 개면 (날짜, 규칙 id) 시드로 하루 동안 고정된 하나를 고른다.
    let messages: [@Sendable (FocusNudgeContext) -> String]
}

// MARK: - 엔진

enum FocusNudgeEngine {
    static func resolve(
        _ context: FocusNudgeContext,
        rules: [FocusNudgeRule] = FocusNudgeCatalog.rules
    ) -> FocusNudge {
        // 우선순위 내림차순, 동순위는 카탈로그 순서. Swift 의 sort 는 안정적이지 않으므로 색인을 함께 비교한다.
        let matched = rules.enumerated()
            .filter { $0.element.condition(context) }
            .min { lhs, rhs in
                if lhs.element.priority != rhs.element.priority {
                    return lhs.element.priority > rhs.element.priority
                }
                return lhs.offset < rhs.offset
            }?.element

        guard let matched, !matched.messages.isEmpty else {
            return FocusNudge(
                ruleID: "none",
                tier: .coldStart,
                badge: "오늘 시작",
                message: "오늘 하루 가볍게 시작해볼까요?"
            )
        }

        let index = stableIndex(count: matched.messages.count, seed: seed(day: context.day, ruleID: matched.id))
        return FocusNudge(
            ruleID: matched.id,
            tier: matched.tier,
            badge: matched.badge,
            message: matched.messages[index](context)
        )
    }

    /// 같은 날 같은 규칙이면 항상 같은 문구가 나오게 한다. SwiftUI body 는 자주 다시 계산되므로
    /// Int.random 을 쓰면 문구가 깜빡이며 바뀐다.
    private static func stableIndex(count: Int, seed: String) -> Int {
        guard count > 1 else { return 0 }
        // String.hashValue 는 실행마다 시드가 달라지므로 직접 djb2 로 계산한다.
        var hash: UInt64 = 5381
        for byte in seed.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return Int(hash % UInt64(count))
    }

    private static func seed(day: Date, ruleID: String) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: day)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)|\(ruleID)"
    }
}

// MARK: - 문구용 서식

enum FocusNudgeFormat {
    static func duration(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return minutes > 0 ? "\(hours)시간 \(minutes)분" : "\(hours)시간"
        }
        return "\(minutes)분"
    }

    static func shortDuration(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        return "\(minutes)m"
    }

    static func percent(_ ratio: Double) -> String {
        "\(Int((ratio * 100).rounded()))%"
    }

    static func clockTime(_ date: Date) -> String {
        // 문구를 만들 때 한 번만 쓰이므로 정적 캐시(비-Sendable) 대신 그때그때 만든다.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.setLocalizedDateFormatFromTemplate("jm")
        return formatter.string(from: date)
    }

    static func taskProgress(remaining: Int, total: Int) -> String {
        total > 0 ? "\(remaining)/\(total)" : "—"
    }

    static func taskCaption(remaining: Int, total: Int, overdue: Int) -> String {
        if overdue > 0 {
            return "남음 \(remaining)개 · 마감 지남 \(overdue)개"
        }
        guard total > 0 else { return "메모에 등록해보세요" }
        return remaining > 0 ? "남음 \(remaining)개" : "모두 끝냈어요"
    }
}

// MARK: - 스냅샷

/// 뷰가 전달받는 묶음. 문구와 그 근거가 되는 지표를 같이 들고 있다.
struct FocusNudgeSnapshot {
    let context: FocusNudgeContext
    let nudge: FocusNudge

    @MainActor
    static func make(
        day: Date = Date(),
        now: Date = Date(),
        modelContext: ModelContext
    ) -> FocusNudgeSnapshot {
        let context = FocusNudgeSnapshotLoader.context(day: day, now: now, modelContext: modelContext)
        return FocusNudgeSnapshot(context: context, nudge: FocusNudgeEngine.resolve(context))
    }
}

// MARK: - 과거 몰입 흐름

struct HistoricalFocusTrendPeriod: Equatable, Sendable {
    let selectedDay: Date
    let recentStart: Date
    let recentEnd: Date
    let previousStart: Date
    let previousEnd: Date

    /// 선택한 날짜를 포함한 최근 7일과 그 직전 7일을 만든다.
    static func ending(
        on day: Date,
        calendar: Calendar = .current
    ) -> HistoricalFocusTrendPeriod {
        let selectedDay = calendar.startOfDay(for: day)

        func addingDays(_ value: Int, to date: Date) -> Date {
            calendar.date(byAdding: .day, value: value, to: date)
                ?? date.addingTimeInterval(Double(value) * 24 * 60 * 60)
        }

        let recentEnd = addingDays(1, to: selectedDay)
        let recentStart = addingDays(-6, to: selectedDay)
        let previousStart = addingDays(-7, to: recentStart)
        return HistoricalFocusTrendPeriod(
            selectedDay: selectedDay,
            recentStart: recentStart,
            recentEnd: recentEnd,
            previousStart: previousStart,
            previousEnd: recentStart
        )
    }
}

struct HistoricalFocusTrendWindow: Equatable, Sendable {
    static let minimumObservedSeconds = 30 * 60

    let completedPomodoroCount: Int
    let pomodoroFocusSeconds: Int
    let reflection: FocusReflectionSummary
    let observedSeconds: Int
    let timerCoveredSeconds: Int
    let categorySwitchCount: Int

    var timerCoverageRatio: Double? {
        guard observedSeconds >= Self.minimumObservedSeconds else { return nil }
        return Double(timerCoveredSeconds) / Double(observedSeconds)
    }

    var categorySwitchesPerRecordedTenMinutes: Double? {
        guard observedSeconds >= Self.minimumObservedSeconds else { return nil }
        return Double(categorySwitchCount) * 10 * 60 / Double(observedSeconds)
    }
}

struct HistoricalFocusTrendSnapshot: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case deepening
        case steady
        case softening
        case collecting
    }

    let period: HistoricalFocusTrendPeriod
    let recent: HistoricalFocusTrendWindow
    let previous: HistoricalFocusTrendWindow

    var focusedResponseDelta: Int? {
        recent.reflection.focusedResponseDelta(
            comparedTo: previous.reflection
        )
    }

    var state: State {
        guard let focusedResponseDelta else { return .collecting }
        if focusedResponseDelta >= FocusReflectionSummary.meaningfulFocusedResponseDelta {
            return .deepening
        }
        if focusedResponseDelta <= -FocusReflectionSummary.meaningfulFocusedResponseDelta {
            return .softening
        }
        return .steady
    }

    @MainActor
    static func make(
        day: Date,
        modelContext: ModelContext
    ) -> HistoricalFocusTrendSnapshot {
        FocusNudgeSnapshotLoader.historicalSnapshot(
            day: day,
            modelContext: modelContext
        )
    }
}

// MARK: - 저장소 → 스냅샷

@MainActor
enum FocusNudgeSnapshotLoader {
    private struct HistoricalSegmentSlice {
        let start: Date
        let end: Date
        let category: String
    }

    /// 대표 카테고리로 부를 최소 세션 수.
    private static let minimumCategorySessionCount = 2
    /// 콜드스타트 판정에서 확인하는 과거 완료 기록 구간(일).
    private static let historyDayCount = 14

    static func historicalSnapshot(
        day: Date,
        modelContext: ModelContext
    ) -> HistoricalFocusTrendSnapshot {
        let calendar = Calendar.current
        let period = HistoricalFocusTrendPeriod.ending(on: day, calendar: calendar)
        let sessions = fetchSessions(
            from: period.previousStart,
            to: period.recentEnd,
            modelContext: modelContext
        ).filter(isCompletedPomodoro)
        let reflectionBySessionID = fetchReflections(
            for: sessions,
            modelContext: modelContext
        )
        let segments = fetchSegments(
            from: period.previousStart,
            to: period.recentEnd,
            modelContext: modelContext
        )

        return HistoricalFocusTrendSnapshot(
            period: period,
            recent: historicalWindow(
                from: period.recentStart,
                to: period.recentEnd,
                sessions: sessions,
                reflectionBySessionID: reflectionBySessionID,
                segments: segments,
                calendar: calendar
            ),
            previous: historicalWindow(
                from: period.previousStart,
                to: period.previousEnd,
                sessions: sessions,
                reflectionBySessionID: reflectionBySessionID,
                segments: segments,
                calendar: calendar
            )
        )
    }

    static func context(day: Date, now: Date, modelContext: ModelContext) -> FocusNudgeContext {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)
        let comparisonPeriod = HistoricalFocusTrendPeriod.ending(
            on: dayStart,
            calendar: calendar
        )
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart),
              let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: dayStart),
              let historyStart = calendar.date(byAdding: .day, value: -historyDayCount, to: dayStart) else {
            return .empty(day: day, now: now)
        }

        let sessions = fetchSessions(from: historyStart, to: dayEnd, modelContext: modelContext)
        let completed = sessions.filter(isCompletedPomodoro)
        let reflectionBySessionID = fetchReflections(for: completed, modelContext: modelContext)

        let todaySessions = completed.filter { $0.startedAt >= dayStart }
        let yesterdaySessions = completed.filter { $0.startedAt >= yesterdayStart && $0.startedAt < dayStart }
        let sameTimeCutoff = yesterdayStart.addingTimeInterval(now.timeIntervalSince(dayStart))
        let recentWeek = completed.filter {
            $0.startedAt >= comparisonPeriod.recentStart
                && $0.startedAt < comparisonPeriod.recentEnd
        }
        let previousWeek = completed.filter {
            $0.startedAt >= comparisonPeriod.previousStart
                && $0.startedAt < comparisonPeriod.previousEnd
        }

        let reasonCounts = recentWeek.reduce(into: [PomodoroIncompleteReason: Int]()) { counts, session in
            guard let reason = reflectionBySessionID[session.id]?.incompleteReason else { return }
            counts[reason, default: 0] += 1
        }
        let topReason = reasonCounts.max { $0.value < $1.value }

        let coverage = coverage(
            dayStart: dayStart,
            dayEnd: min(dayEnd, max(now, dayStart)),
            sessions: sessions.filter { $0.startedAt >= dayStart },
            modelContext: modelContext
        )
        let tasks = taskSummary(dayStart: dayStart, dayEnd: dayEnd, now: now, modelContext: modelContext)
        let recordedDays = Set(
            completed
                .filter { $0.startedAt < dayStart }
                .map { calendar.startOfDay(for: $0.startedAt) }
        )

        return FocusNudgeContext(
            day: dayStart,
            now: now,
            todayCompletedCount: todaySessions.count,
            todayFocusSeconds: todaySessions.reduce(0) { $0 + $1.recordedFocusSeconds },
            yesterdayCountBySameTime: yesterdaySessions.filter { $0.startedAt < sameTimeCutoff }.count,
            yesterdayCompletedCount: yesterdaySessions.count,
            recentReflection: reflectionSummary(
                sessions: recentWeek,
                reflectionBySessionID: reflectionBySessionID
            ),
            previousReflection: reflectionSummary(
                sessions: previousWeek,
                reflectionBySessionID: reflectionBySessionID
            ),
            topCategory: topCategory(sessions: recentWeek),
            topIncompleteReason: topReason?.key,
            topIncompleteReasonCount: topReason?.value ?? 0,
            observedSeconds: coverage.observedSeconds,
            coveredSeconds: coverage.coveredSeconds,
            openTaskCount: tasks.open,
            totalTaskCount: tasks.total,
            overdueTaskCount: tasks.overdue,
            nextTask: tasks.next,
            recordedDayCount: recordedDays.count
        )
    }

    // MARK: 조회

    private static func fetchSessions(from start: Date, to end: Date, modelContext: ModelContext) -> [FocusSession] {
        let descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.startedAt >= start && $0.startedAt < end },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private static func fetchSegments(
        from start: Date,
        to end: Date,
        modelContext: ModelContext
    ) -> [AppUsageSegment] {
        let descriptor = FetchDescriptor<AppUsageSegment>(
            predicate: #Predicate { $0.startTime < end && $0.endTime > start },
            sortBy: [SortDescriptor(\.startTime)]
        )
        return ((try? modelContext.fetch(descriptor)) ?? []).filter {
            !Constants.hiddenLegacyCategories.contains($0.category)
        }
    }

    private static func fetchReflections(
        for sessions: [FocusSession],
        modelContext: ModelContext
    ) -> [UUID: PomodoroReflection] {
        guard !sessions.isEmpty else { return [:] }
        let sessionIDs = sessions.map(\.id)
        let descriptor = FetchDescriptor<PomodoroReflection>(
            predicate: #Predicate { sessionIDs.contains($0.focusSessionID) }
        )
        let reflections = (try? modelContext.fetch(descriptor)) ?? []
        return Dictionary(reflections.map { ($0.focusSessionID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: 지표

    private static func historicalWindow(
        from start: Date,
        to end: Date,
        sessions: [FocusSession],
        reflectionBySessionID: [UUID: PomodoroReflection],
        segments: [AppUsageSegment],
        calendar: Calendar
    ) -> HistoricalFocusTrendWindow {
        let windowSessions = sessions.filter {
            $0.startedAt >= start && $0.startedAt < end
        }
        let experiences = windowSessions
            .compactMap { reflectionBySessionID[$0.id]?.focusExperience }
            .filter { $0 != .unsure }
        let focusedResponseCount = experiences.filter {
            $0 == .deeplyFocused || $0 == .mostlyFocused
        }.count

        let slices = segments.compactMap { segment -> HistoricalSegmentSlice? in
            guard let interval = clip(segment.startTime, segment.endTime, start, end) else {
                return nil
            }
            return HistoricalSegmentSlice(
                start: interval.start,
                end: interval.end,
                category: segment.category
            )
        }
        let observed = merge(slices.map {
            DateInterval(start: $0.start, end: $0.end)
        })
        let focusWindows = merge(windowSessions.compactMap { session -> DateInterval? in
            guard let focusEnd = focusEnd(for: session) else { return nil }
            return clip(session.startedAt, focusEnd, start, end)
        })

        return HistoricalFocusTrendWindow(
            completedPomodoroCount: windowSessions.count,
            pomodoroFocusSeconds: windowSessions.reduce(0) {
                $0 + $1.recordedFocusSeconds
            },
            reflection: FocusReflectionSummary(
                focusedResponseCount: focusedResponseCount,
                validResponseCount: experiences.count
            ),
            observedSeconds: observed.reduce(0) { $0 + Int($1.duration) },
            timerCoveredSeconds: intersectionSeconds(observed, focusWindows),
            categorySwitchCount: categorySwitchCount(
                slices,
                calendar: calendar
            )
        )
    }

    private static func categorySwitchCount(
        _ slices: [HistoricalSegmentSlice],
        calendar: Calendar
    ) -> Int {
        let slicesByDay = Dictionary(grouping: slices) {
            calendar.startOfDay(for: $0.start)
        }

        return slicesByDay.values.reduce(0) { total, daySlices in
            let sorted = daySlices.sorted {
                if $0.start != $1.start { return $0.start < $1.start }
                if $0.end != $1.end { return $0.end < $1.end }
                return $0.category < $1.category
            }
            guard sorted.count > 1 else { return total }

            let switches = zip(sorted, sorted.dropFirst()).reduce(0) {
                count, pair in
                let gap = pair.1.start.timeIntervalSince(pair.0.end)
                guard gap >= 0,
                      gap <= 2 * 60,
                      pair.0.category != pair.1.category else {
                    return count
                }
                return count + 1
            }
            return total + switches
        }
    }

    private static func reflectionSummary(
        sessions: [FocusSession],
        reflectionBySessionID: [UUID: PomodoroReflection]
    ) -> FocusReflectionSummary {
        let experiences = sessions
            .compactMap { reflectionBySessionID[$0.id]?.focusExperience }
            .filter { $0 != .unsure }
        let focusedResponseCount = experiences.filter {
            $0 == .deeplyFocused || $0 == .mostlyFocused
        }.count
        return FocusReflectionSummary(
            focusedResponseCount: focusedResponseCount,
            validResponseCount: experiences.count
        )
    }

    private static func topCategory(sessions: [FocusSession]) -> String? {
        var seconds: [String: Int] = [:]
        var counts: [String: Int] = [:]
        for session in sessions {
            guard let category = session.category,
                  !Constants.hiddenLegacyCategories.contains(category) else { continue }
            seconds[category, default: 0] += session.recordedFocusSeconds
            counts[category, default: 0] += 1
        }
        return seconds
            .filter { (counts[$0.key] ?? 0) >= minimumCategorySessionCount }
            .max { $0.value < $1.value }?
            .key
    }

    /// 오늘 기록된 시간 중 타이머 안에서 보낸 비율의 원재료. 세그먼트가 겹칠 수 있으므로 구간을 합쳐서 센다.
    private static func coverage(
        dayStart: Date,
        dayEnd: Date,
        sessions: [FocusSession],
        modelContext: ModelContext
    ) -> (observedSeconds: Int, coveredSeconds: Int) {
        guard dayEnd > dayStart else { return (0, 0) }

        let descriptor = FetchDescriptor<AppUsageSegment>(
            predicate: #Predicate { $0.startTime < dayEnd && $0.endTime > dayStart }
        )
        let segments = ((try? modelContext.fetch(descriptor)) ?? []).filter {
            !Constants.hiddenLegacyCategories.contains($0.category)
        }

        let observed = merge(segments.compactMap { clip($0.startTime, $0.endTime, dayStart, dayEnd) })
        let windows = merge(sessions.compactMap { session -> DateInterval? in
            guard let end = focusEnd(for: session) else { return nil }
            return clip(session.startedAt, end, dayStart, dayEnd)
        })

        return (
            observed.reduce(0) { $0 + Int($1.duration) },
            intersectionSeconds(observed, windows)
        )
    }

    /// 오늘 예정된 할 일과 아직 끝내지 않은 마감 초과 할 일을 서로 분리해 집계한다.
    private static func taskSummary(
        dayStart: Date,
        dayEnd: Date,
        now: Date,
        modelContext: ModelContext
    ) -> (open: Int, total: Int, overdue: Int, next: FocusNudgeContext.TaskCandidate?) {
        struct ScopedTask {
            let memo: Memo
            let at: Date?
            let isOverdue: Bool
        }

        // Memo 의 날짜 필드는 옵셔널이라 #Predicate 로 다루기 번거롭고, 메모 수는 많지 않으므로 메모리에서 걸러낸다.
        let memos = ((try? modelContext.fetch(FetchDescriptor<Memo>())) ?? []).filter { !$0.isArchivedValue }

        var todayTasks: [ScopedTask] = []
        var candidates: [ScopedTask] = []
        for memo in memos {
            let todayDates = [memo.startDate, memo.deadline]
                .compactMap { $0 }
                .filter { $0 >= dayStart && $0 < dayEnd }
            if let at = todayDates.min() {
                let task = ScopedTask(
                    memo: memo,
                    at: at,
                    isOverdue: (memo.deadline ?? .distantFuture) < now
                )
                todayTasks.append(task)
                candidates.append(task)
            } else if let deadline = memo.deadline, deadline < dayStart, !memo.isCompletedValue {
                candidates.append(ScopedTask(memo: memo, at: deadline, isOverdue: true))
            }
        }

        let openTodayTasks = todayTasks.filter { !$0.memo.isCompletedValue }
        let openCandidates = candidates.filter { !$0.memo.isCompletedValue }
        let upcoming = openCandidates
            .filter { ($0.at ?? .distantPast) >= now }
            .min { ($0.at ?? .distantFuture) < ($1.at ?? .distantFuture) }
        // 다가오는 게 없으면 지난 것 중 가장 최근을 집는다.
        let next = upcoming ?? openCandidates.max {
            ($0.at ?? .distantPast) < ($1.at ?? .distantPast)
        }

        return (
            open: openTodayTasks.count,
            total: todayTasks.count,
            overdue: openCandidates.filter(\.isOverdue).count,
            next: next.map {
                FocusNudgeContext.TaskCandidate(
                    title: taskTitle($0.memo.content),
                    at: $0.at,
                    isOverdue: $0.isOverdue
                )
            }
        )
    }

    private static func taskTitle(_ content: String) -> String {
        let firstLine = content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard !firstLine.isEmpty else { return "제목 없는 할 일" }
        guard firstLine.count > 24 else { return firstLine }
        return String(firstLine.prefix(24)) + "…"
    }

    // MARK: 구간 계산

    private static func merge(_ intervals: [DateInterval]) -> [DateInterval] {
        let sorted = intervals.filter { $0.duration > 0 }.sorted { $0.start < $1.start }
        var merged: [DateInterval] = []
        for interval in sorted {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }
        return merged
    }

    private static func intersectionSeconds(_ lhs: [DateInterval], _ rhs: [DateInterval]) -> Int {
        var total: TimeInterval = 0
        for left in lhs {
            for right in rhs {
                total += left.intersection(with: right)?.duration ?? 0
            }
        }
        return Int(total)
    }

    private static func clip(_ start: Date, _ end: Date, _ lower: Date, _ upper: Date) -> DateInterval? {
        let clippedStart = max(start, lower)
        let clippedEnd = min(end, upper)
        guard clippedEnd > clippedStart else { return nil }
        return DateInterval(start: clippedStart, end: clippedEnd)
    }

    private static func isCompletedPomodoro(_ session: FocusSession) -> Bool {
        guard let endedAt = session.endedAt else { return false }
        let expectedSeconds = max(0, session.focusMinutes) * 60
        guard expectedSeconds > 0 else { return false }
        return session.completed || endedAt.timeIntervalSince(session.startedAt) >= TimeInterval(expectedSeconds)
    }

    private static func focusEnd(for session: FocusSession) -> Date? {
        guard let endedAt = session.endedAt else { return nil }
        let expectedEnd = session.startedAt.addingTimeInterval(TimeInterval(max(0, session.focusMinutes) * 60))
        return min(endedAt, expectedEnd)
    }
}
