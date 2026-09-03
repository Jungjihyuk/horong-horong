import Foundation

/// 통계 상세 화면에서 쓰이는 앱 사용 기록 값 타입.
struct StatsAppUsageRecord: Equatable, Sendable, Identifiable {
    let id: UUID
    let appName: String
    let bundleIdentifier: String
    let category: String
    let date: Date
    let durationSeconds: Int

    init(
        id: UUID = UUID(),
        appName: String,
        bundleIdentifier: String,
        category: String,
        date: Date,
        durationSeconds: Int
    ) {
        self.id = id
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.category = category
        self.date = date
        self.durationSeconds = durationSeconds
    }
}

/// 통계 상세 및 타임라인에서 쓰이는 앱 사용 구간 값 타입.
struct StatsAppUsageSegment: Equatable, Sendable, Identifiable {
    let id: UUID
    let appName: String
    let bundleIdentifier: String
    let category: String
    let startTime: Date
    let endTime: Date
    let isManual: Bool
    let isUserModified: Bool

    init(
        id: UUID = UUID(),
        appName: String,
        bundleIdentifier: String,
        category: String,
        startTime: Date,
        endTime: Date,
        isManual: Bool = false,
        isUserModified: Bool = false
    ) {
        self.id = id
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.category = category
        self.startTime = startTime
        self.endTime = endTime
        self.isManual = isManual
        self.isUserModified = isUserModified
    }

    var durationSeconds: Int {
        max(0, Int(endTime.timeIntervalSince(startTime)))
    }
}

/// 통계 상세에서 쓰이는 집중 세션 요약 값 타입.
struct StatsFocusSession: Equatable, Sendable, Identifiable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date?
    let category: String?
    let markerColorKey: String?
    let taskTitleSnapshot: String?
    let linkedMemoID: UUID?
    let focusMinutes: Int
    let recordedFocusSeconds: Int
    let completed: Bool

    init(
        id: UUID,
        startedAt: Date,
        endedAt: Date?,
        category: String?,
        markerColorKey: String?,
        taskTitleSnapshot: String?,
        linkedMemoID: UUID?,
        focusMinutes: Int,
        recordedFocusSeconds: Int,
        completed: Bool
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.category = category
        self.markerColorKey = markerColorKey
        self.taskTitleSnapshot = taskTitleSnapshot
        self.linkedMemoID = linkedMemoID
        self.focusMinutes = focusMinutes
        self.recordedFocusSeconds = recordedFocusSeconds
        self.completed = completed
    }
}

/// 통계 상세에서 쓰이는 포모도로 회고 값 타입.
struct StatsPomodoroReflection: Equatable, Sendable, Identifiable {
    let id: UUID
    let focusSessionID: UUID
    let focusExperienceRawValue: String
    let progressResultRawValue: String
    let incompleteReasonRawValue: String?
    let answeredAt: Date

    init(
        id: UUID,
        focusSessionID: UUID,
        focusExperienceRawValue: String,
        progressResultRawValue: String,
        incompleteReasonRawValue: String?,
        answeredAt: Date
    ) {
        self.id = id
        self.focusSessionID = focusSessionID
        self.focusExperienceRawValue = focusExperienceRawValue
        self.progressResultRawValue = progressResultRawValue
        self.incompleteReasonRawValue = incompleteReasonRawValue
        self.answeredAt = answeredAt
    }

    var focusExperience: PomodoroFocusExperience? {
        PomodoroFocusExperience(rawValue: focusExperienceRawValue)
    }

    var progressResult: PomodoroProgressResult? {
        PomodoroProgressResult(rawValue: progressResultRawValue)
    }

    var incompleteReason: PomodoroIncompleteReason? {
        incompleteReasonRawValue.flatMap(PomodoroIncompleteReason.init(rawValue:))
    }
}

/// 통계 상세에서 쓰이는 포모도로 할 일 완료 스냅샷 값 타입.
struct StatsPomodoroTaskCompletion: Equatable, Sendable, Identifiable {
    let id: UUID
    let focusSessionID: UUID
    let linkedMemoID: UUID
    let taskTitleSnapshot: String?
    let completedAt: Date

    init(
        id: UUID,
        focusSessionID: UUID,
        linkedMemoID: UUID,
        taskTitleSnapshot: String?,
        completedAt: Date
    ) {
        self.id = id
        self.focusSessionID = focusSessionID
        self.linkedMemoID = linkedMemoID
        self.taskTitleSnapshot = taskTitleSnapshot
        self.completedAt = completedAt
    }
}

/// 통계 상세에서 쓰이는 휴식 후 전환 의도 스냅샷 값 타입.
struct StatsBreakTransitionIntent: Equatable, Sendable, Identifiable {
    let id: UUID
    let breakEndedAt: Date
    let decidedAt: Date
    let decisionRawValue: String
    let previousCategory: String
    let nextCategory: String?

    init(
        id: UUID,
        breakEndedAt: Date,
        decidedAt: Date,
        decisionRawValue: String,
        previousCategory: String,
        nextCategory: String?
    ) {
        self.id = id
        self.breakEndedAt = breakEndedAt
        self.decidedAt = decidedAt
        self.decisionRawValue = decisionRawValue
        self.previousCategory = previousCategory
        self.nextCategory = nextCategory
    }

    var decision: BreakTransitionDecisionKind {
        BreakTransitionDecisionKind(rawValue: decisionRawValue) ?? .unresolvedBreak
    }
}

/// 통계 상세에서 쓰이는 일별 주의 집중 요약 스냅샷 값 타입.
struct StatsAttentionDaySummary: Equatable, Sendable, Identifiable {
    let id: UUID
    let day: Date
    let dayKey: String
    let overallScore: Double
    let flowState: AttentionFlowState
    let selectiveEventCount: Int
    let sustainedEventCount: Int
    let returnEventCount: Int
    let representativeReason: String?

    init(
        id: UUID,
        day: Date,
        dayKey: String,
        overallScore: Double,
        flowState: AttentionFlowState,
        selectiveEventCount: Int,
        sustainedEventCount: Int,
        returnEventCount: Int,
        representativeReason: String?
    ) {
        self.id = id
        self.day = day
        self.dayKey = dayKey
        self.overallScore = overallScore
        self.flowState = flowState
        self.selectiveEventCount = selectiveEventCount
        self.sustainedEventCount = sustainedEventCount
        self.returnEventCount = returnEventCount
        self.representativeReason = representativeReason
    }
}

/// 통계 상세 화면에 필요한 데이터 묶음 스냅샷.
struct StatsDetailSnapshot: Sendable {
    let records: [StatsAppUsageRecord]
    let dailySegments: [StatsAppUsageSegment]
    let weekSegments: [StatsAppUsageSegment]
    let periodSegments: [StatsAppUsageSegment]
    let pomodoroComparisonSessions: [PomodoroSessionBreakdown]
    let timerSessions: [StatsFocusSession]
    let pomodoroReflections: [StatsPomodoroReflection]
    let pomodoroTaskCompletions: [StatsPomodoroTaskCompletion]
    let breakTransitionIntents: [StatsBreakTransitionIntent]
    let aggregateSnapshot: StatsAggregateSnapshot?
    let attentionDaySummaries: [StatsAttentionDaySummary]

    init(
        records: [StatsAppUsageRecord],
        dailySegments: [StatsAppUsageSegment],
        weekSegments: [StatsAppUsageSegment],
        periodSegments: [StatsAppUsageSegment],
        pomodoroComparisonSessions: [PomodoroSessionBreakdown],
        timerSessions: [StatsFocusSession],
        pomodoroReflections: [StatsPomodoroReflection],
        pomodoroTaskCompletions: [StatsPomodoroTaskCompletion],
        breakTransitionIntents: [StatsBreakTransitionIntent],
        aggregateSnapshot: StatsAggregateSnapshot?,
        attentionDaySummaries: [StatsAttentionDaySummary]
    ) {
        self.records = records
        self.dailySegments = dailySegments
        self.weekSegments = weekSegments
        self.periodSegments = periodSegments
        self.pomodoroComparisonSessions = pomodoroComparisonSessions
        self.timerSessions = timerSessions
        self.pomodoroReflections = pomodoroReflections
        self.pomodoroTaskCompletions = pomodoroTaskCompletions
        self.breakTransitionIntents = breakTransitionIntents
        self.aggregateSnapshot = aggregateSnapshot
        self.attentionDaySummaries = attentionDaySummaries
    }
}
