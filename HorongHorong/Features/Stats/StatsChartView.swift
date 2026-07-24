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

struct PomodoroAppUsageEntry: Identifiable, Equatable {
    var id: String { "\(appName)-\(category)" }
    let appName: String
    let category: String
    let durationSeconds: Int
}

struct PomodoroCategoryUsageEntry: Identifiable, Equatable {
    var id: String { category }
    let category: String
    let durationSeconds: Int
}

struct PomodoroCategoryTransition: Identifiable, Equatable {
    var id: String { "\(source)\u{1F}\(target)" }
    let source: String
    let target: String
    let count: Int
}

struct PomodoroContinuousAppUsage: Equatable {
    let appName: String
    let category: String
    let durationSeconds: Int
}

struct PomodoroSessionObservation: Equatable {
    let sessionSeconds: Int
    let recordedSeconds: Int
    let unrecordedSeconds: Int
    let ambiguousOverlapSeconds: Int
    let userModifiedRecordedSeconds: Int
    let appSwitchCount: Int
    let appUsageRunCount: Int
    let categorySwitchCount: Int
    let categoryTransitions: [PomodoroCategoryTransition]
    let longestContinuousAppUsage: PomodoroContinuousAppUsage?
    let apps: [PomodoroAppUsageEntry]
    let categories: [PomodoroCategoryUsageEntry]
    /// 짧은 생산성 관리 확인을 제외하고 전환 계산에 실제로 참여한 앱·웹의 고유 개수.
    var distinctAppWebCount: Int = 0
    /// 전환 흐름에서는 제외했지만 원본 사용 기록에는 남아 있는 짧은 생산성 관리 확인 횟수.
    var shortProductivityManagementVisitCount: Int = 0

    var hasRecords: Bool {
        recordedSeconds > 0
    }

    var attributedSeconds: Int {
        max(0, recordedSeconds - ambiguousOverlapSeconds)
    }

    var averageAppUsageRunSeconds: Double? {
        guard appUsageRunCount > 0 else { return nil }
        return Double(attributedSeconds) / Double(appUsageRunCount)
    }
}

enum PomodoroSessionObservationBuilder {
    private struct StateKey: Hashable {
        let appIdentity: String
        let category: String
    }

    private struct ClippedSegment {
        let appName: String
        let appIdentity: String
        let category: String
        let start: Date
        let end: Date
        let isUserModified: Bool
    }

    private struct AttributedState {
        let key: StateKey
        let appName: String
        let isUserModified: Bool
    }

    private enum IntervalState {
        case attributed(AttributedState)
        case ambiguous(isUserModified: Bool)
    }

    private struct TimelineInterval {
        let start: Date
        let end: Date
        let state: IntervalState

        var duration: TimeInterval {
            max(0, end.timeIntervalSince(start))
        }
    }

    private struct AttributedRun {
        let state: AttributedState
        var end: Date
        var duration: TimeInterval
    }

    private struct AppBehaviorVisit {
        let appIdentity: String
        var category: String
        var duration: TimeInterval
        var isProductivityManagementApp: Bool
    }

    private struct AppBehaviorSummary {
        let visits: [AppBehaviorVisit]
        let distinctAppWebCount: Int
        let shortProductivityManagementVisitCount: Int
    }

    private struct TransitionKey: Hashable {
        let source: String
        let target: String
    }

    static func observation(
        from start: Date,
        to end: Date,
        segments: [AppUsageSegment]
    ) -> PomodoroSessionObservation {
        let sessionSeconds = max(0, Int(end.timeIntervalSince(start)))
        guard end > start else { return emptyObservation(sessionSeconds: sessionSeconds) }

        let clipped = segments.compactMap { segment -> ClippedSegment? in
            let clippedStart = max(segment.startTime, start)
            let clippedEnd = min(segment.endTime, end)
            guard clippedEnd > clippedStart else { return nil }

            let normalizedApp = normalizedApp(
                appName: segment.appName,
                bundleIdentifier: segment.bundleIdentifier
            )
            return ClippedSegment(
                appName: normalizedApp.displayName,
                appIdentity: normalizedApp.identity,
                category: segment.category,
                start: clippedStart,
                end: clippedEnd,
                isUserModified: segment.isUserModified || segment.isManual
            )
        }
        .sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.end != $1.end { return $0.end < $1.end }
            if $0.appIdentity != $1.appIdentity { return $0.appIdentity < $1.appIdentity }
            return $0.category < $1.category
        }

        guard !clipped.isEmpty else { return emptyObservation(sessionSeconds: sessionSeconds) }

        let timeline = hasOverlappingSegments(clipped)
            ? normalizedTimeline(from: clipped)
            : clipped.map {
                TimelineInterval(
                    start: $0.start,
                    end: $0.end,
                    state: .attributed(AttributedState(
                        key: StateKey(appIdentity: $0.appIdentity, category: $0.category),
                        appName: $0.appName,
                        isUserModified: $0.isUserModified
                    ))
                )
            }

        let behaviorSummary = appBehaviorSummary(from: timeline)
        let behaviorVisits = behaviorSummary.visits
        var appDurations: [StateKey: (appName: String, duration: TimeInterval)] = [:]
        var ambiguousOverlapDuration: TimeInterval = 0
        var userModifiedRecordedDuration: TimeInterval = 0
        let appUsageRunCount = behaviorVisits.count
        let appSwitchCount = max(0, appUsageRunCount - 1)
        var categorySwitchCount = 0
        var transitionCounts: [TransitionKey: Int] = [:]
        var previousAttributed: (state: AttributedState, end: Date)?
        var currentRun: AttributedRun?
        var longestUsage: PomodoroContinuousAppUsage?

        func finishCurrentRun() {
            guard let currentRun else { return }
            guard !Constants.isProductivityManagementCategory(
                currentRun.state.key.category
            ) else { return }
            let durationSeconds = max(0, Int(currentRun.duration))
            guard durationSeconds > (longestUsage?.durationSeconds ?? -1) else { return }
            longestUsage = PomodoroContinuousAppUsage(
                appName: currentRun.state.appName,
                category: currentRun.state.key.category,
                durationSeconds: durationSeconds
            )
        }

        for interval in timeline {
            switch interval.state {
            case let .ambiguous(isUserModified):
                ambiguousOverlapDuration += interval.duration
                if isUserModified { userModifiedRecordedDuration += interval.duration }
                previousAttributed = nil
                finishCurrentRun()
                currentRun = nil

            case let .attributed(state):
                if let existing = appDurations[state.key] {
                    appDurations[state.key] = (
                        state.appName,
                        existing.duration + interval.duration
                    )
                } else {
                    appDurations[state.key] = (state.appName, interval.duration)
                }
                if state.isUserModified { userModifiedRecordedDuration += interval.duration }

                let isDirectlyAfterPrevious = previousAttributed.map {
                    isDirectlyAfter($0.end, nextStart: interval.start)
                } ?? false
                if let previous = previousAttributed, isDirectlyAfterPrevious {
                    let previousCategory = previous.state.key.category
                    let currentCategory = state.key.category
                    if previousCategory != Constants.unclassifiedAppCategory,
                       currentCategory != Constants.unclassifiedAppCategory,
                       !Constants.isProductivityManagementCategory(previousCategory),
                       !Constants.isProductivityManagementCategory(currentCategory),
                       previousCategory != currentCategory {
                        categorySwitchCount += 1
                        transitionCounts[
                            TransitionKey(
                                source: previousCategory,
                                target: currentCategory
                            ),
                            default: 0
                        ] += 1
                    }
                }

                if let run = currentRun,
                   run.state.key == state.key,
                   isDirectlyAfter(run.end, nextStart: interval.start) {
                    currentRun?.end = interval.end
                    currentRun?.duration += interval.duration
                } else {
                    finishCurrentRun()
                    currentRun = AttributedRun(
                        state: state,
                        end: interval.end,
                        duration: interval.duration
                    )
                }
                previousAttributed = (state, interval.end)
            }
        }
        finishCurrentRun()

        let rawRecordedDuration = appDurations.values.reduce(ambiguousOverlapDuration) {
            $0 + $1.duration
        }
        let recordedSeconds = min(sessionSeconds, max(0, Int(rawRecordedDuration)))
        var appSecondsByKey = appDurations.mapValues { max(0, Int($0.duration)) }
        var ambiguousOverlapSeconds = max(0, Int(ambiguousOverlapDuration))
        var unallocatedSeconds = recordedSeconds
            - appSecondsByKey.values.reduce(ambiguousOverlapSeconds, +)
        var roundingCandidates = appDurations.map { key, value in
            (
                fraction: value.duration - floor(value.duration),
                sortKey: "app:\(key.appIdentity)\u{1F}\(key.category)",
                appKey: Optional(key)
            )
        }
        if ambiguousOverlapDuration > 0 {
            roundingCandidates.append((
                fraction: ambiguousOverlapDuration - floor(ambiguousOverlapDuration),
                sortKey: "overlap",
                appKey: nil
            ))
        }
        roundingCandidates.sort {
            if $0.fraction != $1.fraction { return $0.fraction > $1.fraction }
            return $0.sortKey < $1.sortKey
        }
        for candidate in roundingCandidates where unallocatedSeconds > 0 {
            if let appKey = candidate.appKey {
                appSecondsByKey[appKey, default: 0] += 1
            } else {
                ambiguousOverlapSeconds += 1
            }
            unallocatedSeconds -= 1
        }

        let apps = appDurations
            .map { key, value in
                PomodoroAppUsageEntry(
                    appName: value.appName,
                    category: key.category,
                    durationSeconds: appSecondsByKey[key] ?? 0
                )
            }
            .filter { $0.durationSeconds > 0 }
            .sorted {
                if $0.durationSeconds != $1.durationSeconds {
                    return $0.durationSeconds > $1.durationSeconds
                }
                if $0.appName != $1.appName { return $0.appName < $1.appName }
                return $0.category < $1.category
            }
        let categories = Dictionary(grouping: apps, by: \.category)
            .map { category, entries in
                PomodoroCategoryUsageEntry(
                    category: category,
                    durationSeconds: entries.reduce(0) { $0 + $1.durationSeconds }
                )
            }
            .sorted {
                if $0.durationSeconds != $1.durationSeconds {
                    return $0.durationSeconds > $1.durationSeconds
                }
                return $0.category < $1.category
            }
        return PomodoroSessionObservation(
            sessionSeconds: sessionSeconds,
            recordedSeconds: recordedSeconds,
            unrecordedSeconds: max(0, sessionSeconds - recordedSeconds),
            ambiguousOverlapSeconds: ambiguousOverlapSeconds,
            userModifiedRecordedSeconds: min(
                recordedSeconds,
                max(0, Int(userModifiedRecordedDuration))
            ),
            appSwitchCount: appSwitchCount,
            appUsageRunCount: appUsageRunCount,
            categorySwitchCount: categorySwitchCount,
            categoryTransitions: transitionCounts
                .map {
                    PomodoroCategoryTransition(
                        source: $0.key.source,
                        target: $0.key.target,
                        count: $0.value
                    )
                }
                .sorted {
                    if $0.count != $1.count { return $0.count > $1.count }
                    if $0.source != $1.source { return $0.source < $1.source }
                    return $0.target < $1.target
                },
            longestContinuousAppUsage: longestUsage,
            apps: apps,
            categories: categories,
            distinctAppWebCount: behaviorSummary.distinctAppWebCount,
            shortProductivityManagementVisitCount:
                behaviorSummary.shortProductivityManagementVisitCount
        )
    }

    private static func appBehaviorSummary(
        from timeline: [TimelineInterval]
    ) -> AppBehaviorSummary {
        var observedVisits: [AppBehaviorVisit] = []

        for interval in timeline {
            guard case let .attributed(state) = interval.state else { continue }
            let isProductivityManagementApp = Constants.isProductivityManagementCategory(
                state.key.category
            )
            if let lastIndex = observedVisits.indices.last,
               observedVisits[lastIndex].appIdentity == state.key.appIdentity {
                observedVisits[lastIndex].duration += interval.duration
                if observedVisits[lastIndex].isProductivityManagementApp
                    && !isProductivityManagementApp {
                    observedVisits[lastIndex].isProductivityManagementApp = false
                    observedVisits[lastIndex].category = state.key.category
                }
            } else {
                observedVisits.append(AppBehaviorVisit(
                    appIdentity: state.key.appIdentity,
                    category: state.key.category,
                    duration: interval.duration,
                    isProductivityManagementApp: isProductivityManagementApp
                ))
            }
        }

        let significantVisits = observedVisits.filter {
            !$0.isProductivityManagementApp
                || $0.duration >= Constants.productivityManagementShortInteractionSeconds
        }
        let shortProductivityManagementVisitCount = observedVisits.filter {
            $0.isProductivityManagementApp
                && $0.duration < Constants.productivityManagementShortInteractionSeconds
        }.count
        var collapsedVisits: [AppBehaviorVisit] = []
        for visit in significantVisits {
            if let lastIndex = collapsedVisits.indices.last,
               collapsedVisits[lastIndex].appIdentity == visit.appIdentity {
                collapsedVisits[lastIndex].duration += visit.duration
                collapsedVisits[lastIndex].isProductivityManagementApp =
                    collapsedVisits[lastIndex].isProductivityManagementApp
                        && visit.isProductivityManagementApp
            } else {
                collapsedVisits.append(visit)
            }
        }
        return AppBehaviorSummary(
            visits: collapsedVisits,
            distinctAppWebCount: Set(collapsedVisits.map(\.appIdentity)).count,
            shortProductivityManagementVisitCount: shortProductivityManagementVisitCount
        )
    }

    private static func normalizedApp(
        appName: String,
        bundleIdentifier: String
    ) -> (displayName: String, identity: String) {
        let trimmedName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBundle = bundleIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if let browserBundle = Constants.browserBundleIds.first(where: {
            let base = $0.lowercased()
            return normalizedBundle == base || normalizedBundle.hasPrefix("\(base).")
        }) {
            let websitePrefix = "\(browserBundle.lowercased()).website."
            if normalizedBundle.hasPrefix(websitePrefix),
               let domain = WebsiteCategoryRule.normalizedDomain(
                   from: String(normalizedBundle.dropFirst(websitePrefix.count))
               ) {
                return (domain, "website:\(domain)")
            }

            let displayName: String
            if trimmedName.hasSuffix(")"),
               let suffixStart = trimmedName.range(of: " (", options: .backwards)?.lowerBound {
                displayName = String(trimmedName[..<suffixStart])
            } else {
                displayName = trimmedName
            }
            return (
                displayName.isEmpty ? "이름 없는 브라우저" : displayName,
                "browser:\(browserBundle.lowercased())"
            )
        }

        let displayName = trimmedName.isEmpty ? "이름 없는 앱" : trimmedName
        let identity = trimmedName.isEmpty
            ? "bundle:\(normalizedBundle)"
            : "name:\(trimmedName.lowercased())"
        return (displayName, identity)
    }

    private static func hasOverlappingSegments(_ segments: [ClippedSegment]) -> Bool {
        guard let first = segments.first else { return false }
        var furthestEnd = first.end
        for segment in segments.dropFirst() {
            if segment.start < furthestEnd { return true }
            furthestEnd = max(furthestEnd, segment.end)
        }
        return false
    }

    private static func normalizedTimeline(
        from segments: [ClippedSegment]
    ) -> [TimelineInterval] {
        let boundaries = Array(Set(segments.flatMap { [$0.start, $0.end] })).sorted()
        return zip(boundaries, boundaries.dropFirst()).compactMap {
            intervalStart, intervalEnd -> TimelineInterval? in
            guard intervalEnd > intervalStart else { return nil }
            let active = segments.filter {
                $0.start < intervalEnd && $0.end > intervalStart
            }
            guard !active.isEmpty else { return nil }

            let grouped = Dictionary(grouping: active) {
                StateKey(appIdentity: $0.appIdentity, category: $0.category)
            }
            guard grouped.count == 1, let group = grouped.first else {
                return TimelineInterval(
                    start: intervalStart,
                    end: intervalEnd,
                    state: .ambiguous(
                        isUserModified: active.contains { $0.isUserModified }
                    )
                )
            }
            let representative = group.value.max {
                if $0.start != $1.start { return $0.start < $1.start }
                return $0.end < $1.end
            }!
            return TimelineInterval(
                start: intervalStart,
                end: intervalEnd,
                state: .attributed(AttributedState(
                    key: group.key,
                    appName: representative.appName,
                    isUserModified: group.value.contains { $0.isUserModified }
                ))
            )
        }
    }

    private static func isDirectlyAfter(_ previousEnd: Date, nextStart: Date) -> Bool {
        let gap = nextStart.timeIntervalSince(previousEnd)
        return gap >= 0 && gap < AppTracker.minimumSegmentSeconds
    }

    private static func emptyObservation(sessionSeconds: Int) -> PomodoroSessionObservation {
        PomodoroSessionObservation(
            sessionSeconds: sessionSeconds,
            recordedSeconds: 0,
            unrecordedSeconds: sessionSeconds,
            ambiguousOverlapSeconds: 0,
            userModifiedRecordedSeconds: 0,
            appSwitchCount: 0,
            appUsageRunCount: 0,
            categorySwitchCount: 0,
            categoryTransitions: [],
            longestContinuousAppUsage: nil,
            apps: [],
            categories: []
        )
    }
}

struct PomodoroSessionBreakdown: Identifiable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let category: String
    let linkedMemoID: UUID?
    let taskTitle: String?
    let durationSeconds: Int
    let plannedDurationSeconds: Int?
    let endKind: FocusSessionEndKind?
    let observation: PomodoroSessionObservation
    /// 집중 동안 입력이 있었던 비율(0~1). nil = 입력 데이터 없음(도입 이전 기록).
    let inputActivityRatio: Double?
    /// 사용자가 지정한 몰입 지도 점 색 키. nil = 카테고리 기본색.
    let markerColorKey: String?

    init(
        id: UUID,
        startedAt: Date,
        endedAt: Date,
        category: String,
        linkedMemoID: UUID?,
        taskTitle: String?,
        durationSeconds: Int,
        observation: PomodoroSessionObservation,
        inputActivityRatio: Double? = nil,
        markerColorKey: String? = nil,
        plannedDurationSeconds: Int? = nil,
        endKind: FocusSessionEndKind? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.category = category
        self.linkedMemoID = linkedMemoID
        self.taskTitle = taskTitle
        self.durationSeconds = durationSeconds
        self.plannedDurationSeconds = plannedDurationSeconds
        self.endKind = endKind
        self.observation = observation
        self.inputActivityRatio = inputActivityRatio
        self.markerColorKey = markerColorKey
    }
}

struct PomodoroTimeSummary: Identifiable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let category: String
    let linkedMemoID: UUID?
    let taskTitle: String?
    let durationSeconds: Int
}

struct PomodoroReflectionOptionCount: Identifiable, Equatable {
    let id: String
    let label: String
    let count: Int
}

struct PomodoroPatternMetrics: Equatable {
    let sessionCount: Int
    let linkedSessionCount: Int
    let durationSeconds: Int
    let sessionsWithAppRecords: Int
    let recordedSeconds: Int
    let unrecordedSeconds: Int
    let ambiguousOverlapSeconds: Int
    let userModifiedRecordedSeconds: Int
    let appSwitchCount: Int
    let categorySwitchCount: Int
    let longestContinuousAppUsage: PomodoroContinuousAppUsage?
    let reflectionCount: Int
    let focusExperienceCounts: [PomodoroReflectionOptionCount]
    let progressResultCounts: [PomodoroReflectionOptionCount]
    let incompleteReasonCounts: [PomodoroReflectionOptionCount]

    var unlinkedSessionCount: Int {
        max(0, sessionCount - linkedSessionCount)
    }
}

struct PomodoroPatternGroup: Identifiable, Equatable {
    let id: String
    let linkedMemoID: UUID?
    let title: String
    let firstStartedAt: Date
    let metrics: PomodoroPatternMetrics
}

struct PomodoroPatternReadModel: Equatable {
    let general: PomodoroPatternMetrics
    let categoryGroups: [PomodoroPatternGroup]
    let taskGroups: [PomodoroPatternGroup]
}

enum PomodoroPatternReadModelBuilder {
    static func build(
        sessions: [PomodoroSessionBreakdown],
        reflections: [PomodoroReflection],
        completions: [PomodoroTaskCompletion] = []
    ) -> PomodoroPatternReadModel {
        let reflectionBySessionID = reflections.reduce(into: [UUID: PomodoroReflection]()) {
            $0[$1.focusSessionID] = $1
        }
        let completionSessionIDs = Set(completions.map(\.focusSessionID))

        let categoryGroups = Dictionary(grouping: sessions, by: \.category)
            .map { category, groupedSessions in
                PomodoroPatternGroup(
                    id: "category:\(category)",
                    linkedMemoID: nil,
                    title: category,
                    firstStartedAt: groupedSessions.map(\.startedAt).min() ?? .distantPast,
                    metrics: metrics(
                        for: groupedSessions,
                        reflectionBySessionID: reflectionBySessionID,
                        completionSessionIDs: completionSessionIDs
                    )
                )
            }
            .sorted { lhs, rhs in
                if lhs.metrics.durationSeconds != rhs.metrics.durationSeconds {
                    return lhs.metrics.durationSeconds > rhs.metrics.durationSeconds
                }
                return lhs.title < rhs.title
            }

        let linkedSessions = sessions.filter { $0.linkedMemoID != nil }
        let taskGroups = Dictionary(grouping: linkedSessions, by: { $0.linkedMemoID! })
            .map { memoID, groupedSessions in
                let orderedSessions = groupedSessions.sorted { $0.startedAt < $1.startedAt }
                let latestTitle = orderedSessions.reversed().compactMap {
                    normalizedText($0.taskTitle)
                }.first
                return PomodoroPatternGroup(
                    id: "memo:\(memoID.uuidString)",
                    linkedMemoID: memoID,
                    title: latestTitle ?? "이름을 확인할 수 없는 할 일",
                    firstStartedAt: orderedSessions.first?.startedAt ?? .distantPast,
                    metrics: metrics(
                        for: groupedSessions,
                        reflectionBySessionID: reflectionBySessionID,
                        completionSessionIDs: completionSessionIDs
                    )
                )
            }
            .sorted { lhs, rhs in
                if lhs.firstStartedAt != rhs.firstStartedAt {
                    return lhs.firstStartedAt < rhs.firstStartedAt
                }
                return lhs.title < rhs.title
            }

        return PomodoroPatternReadModel(
            general: metrics(
                for: sessions,
                reflectionBySessionID: reflectionBySessionID,
                completionSessionIDs: completionSessionIDs
            ),
            categoryGroups: categoryGroups,
            taskGroups: taskGroups
        )
    }

    private static func metrics(
        for sessions: [PomodoroSessionBreakdown],
        reflectionBySessionID: [UUID: PomodoroReflection],
        completionSessionIDs: Set<UUID>
    ) -> PomodoroPatternMetrics {
        var longestContinuousAppUsage: PomodoroContinuousAppUsage?
        for usage in sessions.compactMap(\.observation.longestContinuousAppUsage) {
            if usage.durationSeconds > (longestContinuousAppUsage?.durationSeconds ?? -1) {
                longestContinuousAppUsage = usage
            }
        }

        let matchedReflections = sessions.compactMap { session -> (UUID, PomodoroReflection)? in
            reflectionBySessionID[session.id].map { (session.id, $0) }
        }
        let focusRawValues = matchedReflections.map { $0.1.focusExperienceRawValue }
        let progressRawValues = matchedReflections.map { sessionID, reflection in
            if reflection.progressResultRawValue == PomodoroProgressResult.completedAsPlanned.rawValue,
               completionSessionIDs.contains(sessionID) {
                return "linked_task_completed"
            }
            return reflection.progressResultRawValue
        }
        let incompleteRawValues = matchedReflections.compactMap {
            $0.1.incompleteReasonRawValue
        }

        let focusOptions = PomodoroFocusExperience.allCases.map {
            (id: $0.rawValue, label: $0.label)
        }
        let progressOptions = [
            (
                id: "linked_task_completed",
                label: PomodoroProgressResult.completedAsPlanned.label(
                    recordsLinkedTaskCompletion: true
                )
            )
        ] + PomodoroProgressResult.allCases.map {
            (id: $0.rawValue, label: $0.label)
        }
        let incompleteOptions = PomodoroIncompleteReason.allCases.map {
            (id: $0.rawValue, label: $0.label)
        }

        return PomodoroPatternMetrics(
            sessionCount: sessions.count,
            linkedSessionCount: sessions.filter { $0.linkedMemoID != nil }.count,
            durationSeconds: sessions.reduce(0) { $0 + $1.durationSeconds },
            sessionsWithAppRecords: sessions.filter(\.observation.hasRecords).count,
            recordedSeconds: sessions.reduce(0) { $0 + $1.observation.recordedSeconds },
            unrecordedSeconds: sessions.reduce(0) { $0 + $1.observation.unrecordedSeconds },
            ambiguousOverlapSeconds: sessions.reduce(0) {
                $0 + $1.observation.ambiguousOverlapSeconds
            },
            userModifiedRecordedSeconds: sessions.reduce(0) {
                $0 + $1.observation.userModifiedRecordedSeconds
            },
            appSwitchCount: sessions.reduce(0) { $0 + $1.observation.appSwitchCount },
            categorySwitchCount: sessions.reduce(0) {
                $0 + $1.observation.categorySwitchCount
            },
            longestContinuousAppUsage: longestContinuousAppUsage,
            reflectionCount: matchedReflections.count,
            focusExperienceCounts: optionCounts(
                rawValues: focusRawValues,
                options: focusOptions,
                unknownID: "unknown_focus_experience"
            ),
            progressResultCounts: optionCounts(
                rawValues: progressRawValues,
                options: progressOptions,
                unknownID: "unknown_progress_result"
            ),
            incompleteReasonCounts: optionCounts(
                rawValues: incompleteRawValues,
                options: incompleteOptions,
                unknownID: "unknown_incomplete_reason"
            )
        )
    }

    private static func optionCounts(
        rawValues: [String],
        options: [(id: String, label: String)],
        unknownID: String
    ) -> [PomodoroReflectionOptionCount] {
        let counts = Dictionary(grouping: rawValues, by: { $0 }).mapValues(\.count)
        var result = options.compactMap { option -> PomodoroReflectionOptionCount? in
            guard let count = counts[option.id] else { return nil }
            return PomodoroReflectionOptionCount(
                id: option.id,
                label: option.label,
                count: count
            )
        }
        let knownCount = result.reduce(0) { $0 + $1.count }
        if rawValues.count > knownCount {
            result.append(
                PomodoroReflectionOptionCount(
                    id: unknownID,
                    label: "확인할 수 없는 응답",
                    count: rawValues.count - knownCount
                )
            )
        }
        return result
    }

    private static func normalizedText(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum PomodoroFocusComparisonGroup: String, CaseIterable, Identifiable {
    case focused
    case difficult
    case unsure

    var id: String { rawValue }

    var label: String {
        switch self {
        case .focused: return "집중이 잘 됐던 때"
        case .difficult: return "집중이 어려웠던 때"
        case .unsure: return "잘 모르겠음"
        }
    }

    static func group(for rawValue: String) -> PomodoroFocusComparisonGroup? {
        switch rawValue {
        case PomodoroFocusExperience.deeplyFocused.rawValue,
             PomodoroFocusExperience.mostlyFocused.rawValue:
            return .focused
        case PomodoroFocusExperience.frequentlyDistracted.rawValue,
             PomodoroFocusExperience.difficultToFocus.rawValue:
            return .difficult
        case PomodoroFocusExperience.unsure.rawValue:
            return .unsure
        default:
            return nil
        }
    }
}

struct PomodoroBehaviorDistribution: Equatable {
    let missingBehaviorRecordSessionCount: Int
    let qualityExcludedSessionCount: Int
    let sessionsWithAmbiguousRecords: Int
    let appSwitchesPerAttributedTenMinutes: [Double]
    let categorySwitchesPerAttributedTenMinutes: [Double]
    let longestContinuousAppCategoryRatios: [Double]

    var comparableSessionCount: Int {
        appSwitchesPerAttributedTenMinutes.count
    }

    var medianAppSwitchesPerAttributedTenMinutes: Double? {
        Self.median(appSwitchesPerAttributedTenMinutes)
    }

    var medianCategorySwitchesPerAttributedTenMinutes: Double? {
        Self.median(categorySwitchesPerAttributedTenMinutes)
    }

    var medianLongestContinuousAppCategoryRatio: Double? {
        Self.median(longestContinuousAppCategoryRatios)
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}

struct PomodoroFocusComparisonMetrics: Equatable {
    let group: PomodoroFocusComparisonGroup
    let reflectionSessionCount: Int
    let behavior: PomodoroBehaviorDistribution

    var missingBehaviorRecordSessionCount: Int {
        behavior.missingBehaviorRecordSessionCount
    }

    var qualityExcludedSessionCount: Int {
        behavior.qualityExcludedSessionCount
    }

    var sessionsWithAmbiguousRecords: Int {
        behavior.sessionsWithAmbiguousRecords
    }

    var appSwitchesPerAttributedTenMinutes: [Double] {
        behavior.appSwitchesPerAttributedTenMinutes
    }

    var categorySwitchesPerAttributedTenMinutes: [Double] {
        behavior.categorySwitchesPerAttributedTenMinutes
    }

    var longestContinuousAppCategoryRatios: [Double] {
        behavior.longestContinuousAppCategoryRatios
    }

    var comparableSessionCount: Int {
        behavior.comparableSessionCount
    }

    var medianAppSwitchesPerAttributedTenMinutes: Double? {
        behavior.medianAppSwitchesPerAttributedTenMinutes
    }

    var medianCategorySwitchesPerAttributedTenMinutes: Double? {
        behavior.medianCategorySwitchesPerAttributedTenMinutes
    }

    var medianLongestContinuousAppCategoryRatio: Double? {
        behavior.medianLongestContinuousAppCategoryRatio
    }
}

enum PomodoroFocusComparisonQualityPolicy {
    static let minimumRecordedCoverage = 0.8
    static let maximumAmbiguousOverlapRatio = 0.1

    static func includes(_ observation: PomodoroSessionObservation) -> Bool {
        guard observation.sessionSeconds > 0 else { return false }
        let sessionSeconds = Double(observation.sessionSeconds)
        let recordedCoverage = Double(observation.recordedSeconds) / sessionSeconds
        let ambiguousRatio = Double(observation.ambiguousOverlapSeconds) / sessionSeconds
        return recordedCoverage >= minimumRecordedCoverage
            && ambiguousRatio <= maximumAmbiguousOverlapRatio
    }
}

struct PomodoroBehaviorMeasurement: Equatable {
    let appSwitchesPerAttributedTenMinutes: Double
    let categorySwitchesPerAttributedTenMinutes: Double
    let longestContinuousAppCategoryRatio: Double
}

enum PomodoroBehaviorMeasurementHoldReason: Equatable {
    case missingBehaviorRecord
    case qualityExcluded

    var label: String {
        switch self {
        case .missingBehaviorRecord:
            return "앱 기록 없음"
        case .qualityExcluded:
            return "기록 범위·겹침 기준 밖"
        }
    }
}

enum PomodoroBehaviorMeasurementResult: Equatable {
    case measured(PomodoroBehaviorMeasurement, excludedAmbiguousTime: Bool)
    case calculationHeld(PomodoroBehaviorMeasurementHoldReason)
}

enum PomodoroBehaviorMeasurementBuilder {
    static func build(
        observation: PomodoroSessionObservation
    ) -> PomodoroBehaviorMeasurementResult {
        let attributedSeconds = observation.attributedSeconds
        guard observation.sessionSeconds > 0,
              observation.recordedSeconds > 0 else {
            return .calculationHeld(.missingBehaviorRecord)
        }
        guard PomodoroFocusComparisonQualityPolicy.includes(observation) else {
            return .calculationHeld(.qualityExcluded)
        }
        guard attributedSeconds > 0,
              let longest = observation.longestContinuousAppUsage else {
            return .calculationHeld(.missingBehaviorRecord)
        }

        let denominator = Double(attributedSeconds)
        return .measured(
            PomodoroBehaviorMeasurement(
                appSwitchesPerAttributedTenMinutes:
                    Double(observation.appSwitchCount) / denominator * 600,
                categorySwitchesPerAttributedTenMinutes:
                    Double(observation.categorySwitchCount) / denominator * 600,
                longestContinuousAppCategoryRatio:
                    min(1, max(0, Double(longest.durationSeconds) / denominator))
            ),
            excludedAmbiguousTime: observation.ambiguousOverlapSeconds > 0
        )
    }
}

enum PomodoroBehaviorDistributionBuilder {
    static func build(
        sessions: [PomodoroSessionBreakdown]
    ) -> PomodoroBehaviorDistribution {
        var appSwitchRates: [Double] = []
        var categorySwitchRates: [Double] = []
        var longestRatios: [Double] = []
        var missingBehaviorRecordSessionCount = 0
        var qualityExcludedSessionCount = 0
        var sessionsWithAmbiguousRecords = 0

        for session in sessions {
            switch PomodoroBehaviorMeasurementBuilder.build(
                observation: session.observation
            ) {
            case let .calculationHeld(reason):
                switch reason {
                case .missingBehaviorRecord:
                    missingBehaviorRecordSessionCount += 1
                case .qualityExcluded:
                    qualityExcludedSessionCount += 1
                }
            case let .measured(measurement, excludedAmbiguousTime):
                if excludedAmbiguousTime {
                    sessionsWithAmbiguousRecords += 1
                }
                appSwitchRates.append(measurement.appSwitchesPerAttributedTenMinutes)
                categorySwitchRates.append(
                    measurement.categorySwitchesPerAttributedTenMinutes
                )
                longestRatios.append(measurement.longestContinuousAppCategoryRatio)
            }
        }

        return PomodoroBehaviorDistribution(
            missingBehaviorRecordSessionCount: missingBehaviorRecordSessionCount,
            qualityExcludedSessionCount: qualityExcludedSessionCount,
            sessionsWithAmbiguousRecords: sessionsWithAmbiguousRecords,
            appSwitchesPerAttributedTenMinutes: appSwitchRates,
            categorySwitchesPerAttributedTenMinutes: categorySwitchRates,
            longestContinuousAppCategoryRatios: longestRatios
        )
    }
}

struct PomodoroBehaviorConditions: Equatable {
    let maximumAppSwitchesPerAttributedTenMinutes: Double?
    let maximumCategorySwitchesPerAttributedTenMinutes: Double?
    let minimumLongestContinuousAppCategoryRatio: Double?

    init(
        maximumAppSwitchesPerAttributedTenMinutes: Double? = nil,
        maximumCategorySwitchesPerAttributedTenMinutes: Double? = nil,
        minimumLongestContinuousAppCategoryRatio: Double? = nil
    ) {
        self.maximumAppSwitchesPerAttributedTenMinutes =
            maximumAppSwitchesPerAttributedTenMinutes.map {
                ($0 * 10).rounded() / 10
            }
        self.maximumCategorySwitchesPerAttributedTenMinutes =
            maximumCategorySwitchesPerAttributedTenMinutes.map {
                ($0 * 10).rounded() / 10
            }
        self.minimumLongestContinuousAppCategoryRatio =
            minimumLongestContinuousAppCategoryRatio.map {
                ($0 * 100).rounded() / 100
            }
    }

    init(conditionSet: CategoryBehaviorConditionSet) {
        self.init(
            maximumAppSwitchesPerAttributedTenMinutes:
                conditionSet.maximumAppSwitchesPerAttributedTenMinutes,
            maximumCategorySwitchesPerAttributedTenMinutes:
                conditionSet.maximumCategorySwitchesPerAttributedTenMinutes,
            minimumLongestContinuousAppCategoryRatio:
                conditionSet.minimumLongestContinuousAppCategoryRatio
        )
    }

    var conditionCount: Int {
        [
            maximumAppSwitchesPerAttributedTenMinutes,
            maximumCategorySwitchesPerAttributedTenMinutes,
            minimumLongestContinuousAppCategoryRatio,
        ].compactMap { $0 }.count
    }
}

enum PomodoroBehaviorConditionEvaluation: Equatable {
    case noConditions
    case calculationHeld(PomodoroBehaviorMeasurementHoldReason)
    case evaluated(matchedConditionCount: Int, totalConditionCount: Int)
}

struct PomodoroBehaviorConditionPreview: Equatable {
    let totalSessionCount: Int
    let evaluatedSessionCount: Int
    let missingBehaviorRecordSessionCount: Int
    let qualityExcludedSessionCount: Int
    let matchCounts: [Int: Int]
}

enum PomodoroBehaviorConditionEvaluator {
    static func evaluate(
        observation: PomodoroSessionObservation,
        conditions: PomodoroBehaviorConditions
    ) -> PomodoroBehaviorConditionEvaluation {
        guard conditions.conditionCount > 0 else { return .noConditions }
        switch PomodoroBehaviorMeasurementBuilder.build(observation: observation) {
        case let .calculationHeld(reason):
            return .calculationHeld(reason)
        case let .measured(measurement, _):
            let visibleAppSwitchRate =
                (measurement.appSwitchesPerAttributedTenMinutes * 10).rounded() / 10
            let visibleCategorySwitchRate =
                (measurement.categorySwitchesPerAttributedTenMinutes * 10).rounded() / 10
            let visibleLongestRatio =
                (measurement.longestContinuousAppCategoryRatio * 100).rounded() / 100
            var matchedConditionCount = 0
            if let maximum = conditions.maximumAppSwitchesPerAttributedTenMinutes,
               visibleAppSwitchRate <= maximum {
                matchedConditionCount += 1
            }
            if let maximum = conditions.maximumCategorySwitchesPerAttributedTenMinutes,
               visibleCategorySwitchRate <= maximum {
                matchedConditionCount += 1
            }
            if let minimum = conditions.minimumLongestContinuousAppCategoryRatio,
               visibleLongestRatio >= minimum {
                matchedConditionCount += 1
            }
            return .evaluated(
                matchedConditionCount: matchedConditionCount,
                totalConditionCount: conditions.conditionCount
            )
        }
    }

    static func preview(
        sessions: [PomodoroSessionBreakdown],
        category: String,
        conditions: PomodoroBehaviorConditions
    ) -> PomodoroBehaviorConditionPreview {
        let scopedSessions = sessions.filter { $0.category == category }
        var evaluatedSessionCount = 0
        var missingBehaviorRecordSessionCount = 0
        var qualityExcludedSessionCount = 0
        var matchCounts: [Int: Int] = [:]

        for session in scopedSessions {
            switch evaluate(observation: session.observation, conditions: conditions) {
            case .noConditions:
                continue
            case let .calculationHeld(reason):
                switch reason {
                case .missingBehaviorRecord:
                    missingBehaviorRecordSessionCount += 1
                case .qualityExcluded:
                    qualityExcludedSessionCount += 1
                }
            case let .evaluated(matchedConditionCount, _):
                evaluatedSessionCount += 1
                matchCounts[matchedConditionCount, default: 0] += 1
            }
        }

        return PomodoroBehaviorConditionPreview(
            totalSessionCount: scopedSessions.count,
            evaluatedSessionCount: evaluatedSessionCount,
            missingBehaviorRecordSessionCount: missingBehaviorRecordSessionCount,
            qualityExcludedSessionCount: qualityExcludedSessionCount,
            matchCounts: matchCounts
        )
    }
}

struct PomodoroBehaviorConditionDraft: Equatable {
    var usesMaximumAppSwitches: Bool
    var maximumAppSwitchesText: String
    var usesMaximumCategorySwitches: Bool
    var maximumCategorySwitchesText: String
    var usesMinimumLongestContinuousRatio: Bool
    var minimumLongestContinuousPercentText: String

    init(conditionSet: CategoryBehaviorConditionSet? = nil) {
        let appSwitches = conditionSet?.maximumAppSwitchesPerAttributedTenMinutes
        let categorySwitches = conditionSet?.maximumCategorySwitchesPerAttributedTenMinutes
        let continuousRatio = conditionSet?.minimumLongestContinuousAppCategoryRatio
        usesMaximumAppSwitches = appSwitches != nil
        maximumAppSwitchesText = appSwitches.map(Self.rateText) ?? ""
        usesMaximumCategorySwitches = categorySwitches != nil
        maximumCategorySwitchesText = categorySwitches.map(Self.rateText) ?? ""
        usesMinimumLongestContinuousRatio = continuousRatio != nil
        minimumLongestContinuousPercentText = continuousRatio.map {
            String(Int(($0 * 100).rounded()))
        } ?? ""
    }

    var parsedMaximumAppSwitches: Double? {
        guard usesMaximumAppSwitches else { return nil }
        return Self.nonnegativeNumber(maximumAppSwitchesText)
    }

    var parsedMaximumCategorySwitches: Double? {
        guard usesMaximumCategorySwitches else { return nil }
        return Self.nonnegativeNumber(maximumCategorySwitchesText)
    }

    var parsedMinimumLongestContinuousRatio: Double? {
        guard usesMinimumLongestContinuousRatio,
              let percent = Self.number(minimumLongestContinuousPercentText),
              (0...100).contains(percent) else {
            return nil
        }
        return percent.rounded() / 100
    }

    var conditions: PomodoroBehaviorConditions? {
        guard enabledConditionCount > 0, validationMessage == nil else { return nil }
        return PomodoroBehaviorConditions(
            maximumAppSwitchesPerAttributedTenMinutes: parsedMaximumAppSwitches,
            maximumCategorySwitchesPerAttributedTenMinutes: parsedMaximumCategorySwitches,
            minimumLongestContinuousAppCategoryRatio:
                parsedMinimumLongestContinuousRatio
        )
    }

    var validationMessage: String? {
        guard enabledConditionCount > 0 else {
            return "사용할 비교 기준을 하나 이상 켜 주세요."
        }
        if usesMaximumAppSwitches, parsedMaximumAppSwitches == nil {
            return "앱 전환 최대값을 0 이상의 숫자로 직접 입력해 주세요."
        }
        if usesMaximumCategorySwitches, parsedMaximumCategorySwitches == nil {
            return "카테고리 전환 최대값을 0 이상의 숫자로 직접 입력해 주세요."
        }
        if usesMinimumLongestContinuousRatio,
           parsedMinimumLongestContinuousRatio == nil {
            return "이어진 비율의 최소값을 0%에서 100% 사이로 입력해 주세요."
        }
        return nil
    }

    var enabledConditionCount: Int {
        [
            usesMaximumAppSwitches,
            usesMaximumCategorySwitches,
            usesMinimumLongestContinuousRatio,
        ].filter { $0 }.count
    }

    mutating func setMaximumAppSwitches(_ value: Double) {
        maximumAppSwitchesText = Self.rateText(value)
    }

    mutating func setMaximumCategorySwitches(_ value: Double) {
        maximumCategorySwitchesText = Self.rateText(value)
    }

    mutating func setMinimumLongestContinuousPercent(_ value: Double) {
        minimumLongestContinuousPercentText = String(Int(value.rounded()))
    }

    private static func rateText(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private static func nonnegativeNumber(_ text: String) -> Double? {
        guard let value = number(text), value >= 0 else { return nil }
        return (value * 10).rounded() / 10
    }

    private static func number(_ text: String) -> Double? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite else { return nil }
        return value
    }
}

struct PomodoroFocusComparisonReadModel: Equatable {
    let scopedSessionCount: Int
    let matchedReflectionCount: Int
    let unknownReflectionCount: Int
    let focused: PomodoroFocusComparisonMetrics
    let difficult: PomodoroFocusComparisonMetrics
    let unsure: PomodoroFocusComparisonMetrics

    var comparedGroups: [PomodoroFocusComparisonMetrics] {
        [focused, difficult]
    }

    var appSwitchDomainMaximum: Double {
        max(
            1,
            comparedGroups
                .flatMap(\.appSwitchesPerAttributedTenMinutes)
                .max() ?? 0
        )
    }

    var categorySwitchDomainMaximum: Double {
        max(
            1,
            comparedGroups
                .flatMap(\.categorySwitchesPerAttributedTenMinutes)
                .max() ?? 0
        )
    }
}

struct PomodoroFocusComparisonTaskOption: Identifiable, Equatable {
    let id: UUID
    let title: String
    let firstStartedAt: Date
}

enum PomodoroFocusComparisonBuilder {
    static func build(
        sessions: [PomodoroSessionBreakdown],
        reflections: [PomodoroReflection],
        category: String? = nil,
        linkedMemoID: UUID? = nil
    ) -> PomodoroFocusComparisonReadModel {
        let scopedSessions = sessions.filter { session in
            let matchesCategory = category.map { session.category == $0 } ?? true
            let matchesTask = linkedMemoID.map { session.linkedMemoID == $0 } ?? true
            return matchesCategory && matchesTask
        }
        let reflectionBySessionID = reflections.reduce(into: [UUID: PomodoroReflection]()) {
            $0[$1.focusSessionID] = $1
        }
        var groupedSessions: [PomodoroFocusComparisonGroup: [PomodoroSessionBreakdown]] = [:]
        var matchedReflectionCount = 0
        var unknownReflectionCount = 0

        for session in scopedSessions {
            guard let reflection = reflectionBySessionID[session.id] else { continue }
            matchedReflectionCount += 1
            guard let group = PomodoroFocusComparisonGroup.group(
                for: reflection.focusExperienceRawValue
            ) else {
                unknownReflectionCount += 1
                continue
            }
            groupedSessions[group, default: []].append(session)
        }

        return PomodoroFocusComparisonReadModel(
            scopedSessionCount: scopedSessions.count,
            matchedReflectionCount: matchedReflectionCount,
            unknownReflectionCount: unknownReflectionCount,
            focused: metrics(for: .focused, sessions: groupedSessions[.focused] ?? []),
            difficult: metrics(for: .difficult, sessions: groupedSessions[.difficult] ?? []),
            unsure: metrics(for: .unsure, sessions: groupedSessions[.unsure] ?? [])
        )
    }

    static func taskOptions(
        sessions: [PomodoroSessionBreakdown],
        category: String? = nil
    ) -> [PomodoroFocusComparisonTaskOption] {
        let scopedSessions = sessions.filter { session in
            session.linkedMemoID != nil
                && (category.map { session.category == $0 } ?? true)
        }
        return Dictionary(grouping: scopedSessions, by: { $0.linkedMemoID! })
            .map { memoID, groupedSessions in
                let ordered = groupedSessions.sorted { $0.startedAt < $1.startedAt }
                let latestTitle = ordered.reversed().compactMap {
                    normalizedText($0.taskTitle)
                }.first
                return PomodoroFocusComparisonTaskOption(
                    id: memoID,
                    title: latestTitle ?? "이름을 확인할 수 없는 할 일",
                    firstStartedAt: ordered.first?.startedAt ?? .distantPast
                )
            }
            .sorted { lhs, rhs in
                if lhs.firstStartedAt != rhs.firstStartedAt {
                    return lhs.firstStartedAt < rhs.firstStartedAt
                }
                return lhs.title < rhs.title
            }
    }

    private static func metrics(
        for group: PomodoroFocusComparisonGroup,
        sessions: [PomodoroSessionBreakdown]
    ) -> PomodoroFocusComparisonMetrics {
        return PomodoroFocusComparisonMetrics(
            group: group,
            reflectionSessionCount: sessions.count,
            behavior: PomodoroBehaviorDistributionBuilder.build(sessions: sessions)
        )
    }

    private static func normalizedText(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct PomodoroLinkedTaskReflectionCounts: Equatable {
    let answeredCount: Int
    let unansweredCount: Int
    let focusedCount: Int
    let difficultCount: Int
    let unsureCount: Int
    let unknownCount: Int
}

struct PomodoroLinkedTaskComparisonItem: Identifiable, Equatable {
    let id: UUID
    let title: String
    let firstStartedAt: Date
    let totalSessionCount: Int
    let totalDurationSeconds: Int
    let behavior: PomodoroBehaviorDistribution
    let reflections: PomodoroLinkedTaskReflectionCounts
}

struct PomodoroLinkedTaskComparisonReadModel: Equatable {
    let category: String
    let items: [PomodoroLinkedTaskComparisonItem]

    var appSwitchDomainMaximum: Double {
        max(
            1,
            items
                .flatMap(\.behavior.appSwitchesPerAttributedTenMinutes)
                .max() ?? 0
        )
    }

    var categorySwitchDomainMaximum: Double {
        max(
            1,
            items
                .flatMap(\.behavior.categorySwitchesPerAttributedTenMinutes)
                .max() ?? 0
        )
    }
}

enum PomodoroLinkedTaskComparisonBuilder {
    static func build(
        sessions: [PomodoroSessionBreakdown],
        reflections: [PomodoroReflection],
        category: String
    ) -> PomodoroLinkedTaskComparisonReadModel {
        guard !category.isEmpty else {
            return PomodoroLinkedTaskComparisonReadModel(category: category, items: [])
        }
        let reflectionBySessionID = reflections.reduce(into: [UUID: PomodoroReflection]()) {
            $0[$1.focusSessionID] = $1
        }
        let scopedSessions = sessions.filter {
            $0.category == category && $0.linkedMemoID != nil
        }
        let items = Dictionary(grouping: scopedSessions, by: { $0.linkedMemoID! })
            .map { memoID, groupedSessions in
                let ordered = groupedSessions.sorted { $0.startedAt < $1.startedAt }
                let title = ordered.reversed().compactMap {
                    normalizedText($0.taskTitle)
                }.first ?? "이름을 확인할 수 없는 할 일"
                var answeredCount = 0
                var focusedCount = 0
                var difficultCount = 0
                var unsureCount = 0
                var unknownCount = 0

                for session in ordered {
                    guard let reflection = reflectionBySessionID[session.id] else { continue }
                    answeredCount += 1
                    switch PomodoroFocusComparisonGroup.group(
                        for: reflection.focusExperienceRawValue
                    ) {
                    case .focused:
                        focusedCount += 1
                    case .difficult:
                        difficultCount += 1
                    case .unsure:
                        unsureCount += 1
                    case nil:
                        unknownCount += 1
                    }
                }

                return PomodoroLinkedTaskComparisonItem(
                    id: memoID,
                    title: title,
                    firstStartedAt: ordered.first?.startedAt ?? .distantPast,
                    totalSessionCount: ordered.count,
                    totalDurationSeconds: ordered.reduce(0) {
                        $0 + $1.durationSeconds
                    },
                    behavior: PomodoroBehaviorDistributionBuilder.build(
                        sessions: ordered
                    ),
                    reflections: PomodoroLinkedTaskReflectionCounts(
                        answeredCount: answeredCount,
                        unansweredCount: max(0, ordered.count - answeredCount),
                        focusedCount: focusedCount,
                        difficultCount: difficultCount,
                        unsureCount: unsureCount,
                        unknownCount: unknownCount
                    )
                )
            }
            .sorted { lhs, rhs in
                if lhs.firstStartedAt != rhs.firstStartedAt {
                    return lhs.firstStartedAt < rhs.firstStartedAt
                }
                return lhs.title < rhs.title
            }

        return PomodoroLinkedTaskComparisonReadModel(
            category: category,
            items: items
        )
    }

    private static func normalizedText(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum PomodoroComparisonPeriodBuilder {
    static func build(
        sessions: [FocusSession],
        segments: [AppUsageSegment],
        periodStart: Date,
        periodEnd: Date
    ) -> [PomodoroSessionBreakdown] {
        let scopedSessions = sessions.compactMap { session -> (FocusSession, Date)? in
            guard session.startedAt >= periodStart,
                  session.startedAt < periodEnd,
                  isCompleted(session),
                  let end = focusEnd(for: session),
                  end > session.startedAt else {
                return nil
            }
            return (session, end)
        }
        .sorted { $0.0.startedAt < $1.0.startedAt }
        var firstCandidateIndex = 0

        return scopedSessions.map { session, end in
            while firstCandidateIndex < segments.count,
                  segments[firstCandidateIndex].endTime <= session.startedAt {
                firstCandidateIndex += 1
            }
            var endIndex = firstCandidateIndex
            while endIndex < segments.count,
                  segments[endIndex].startTime < end {
                endIndex += 1
            }
            let overlappingSegments = Array(segments[firstCandidateIndex..<endIndex])

            return PomodoroSessionBreakdown(
                id: session.id,
                startedAt: session.startedAt,
                endedAt: end,
                category: session.category ?? Constants.defaultFocusCategory,
                linkedMemoID: session.linkedMemoID,
                taskTitle: session.taskTitleSnapshot,
                durationSeconds: session.recordedFocusSeconds,
                observation: PomodoroSessionObservationBuilder.observation(
                    from: session.startedAt,
                    to: end,
                    segments: overlappingSegments
                ),
                inputActivityRatio: session.inputActiveSeconds.map {
                    Double($0) / Double(max(1, session.recordedFocusSeconds))
                },
                markerColorKey: session.markerColorKey,
                plannedDurationSeconds: max(0, session.focusMinutes) * 60,
                endKind: session.endKind
            )
        }
    }

    static func focusEnd(for session: FocusSession) -> Date? {
        guard let endedAt = session.endedAt else { return nil }
        let expectedEnd = session.startedAt.addingTimeInterval(
            TimeInterval(max(0, session.focusMinutes) * 60)
        )
        return min(endedAt, expectedEnd)
    }

    static func isCompleted(_ session: FocusSession) -> Bool {
        guard let endedAt = session.endedAt else { return false }
        let expectedSeconds = max(0, session.focusMinutes) * 60
        guard expectedSeconds > 0 else { return false }
        return session.completed
            || endedAt.timeIntervalSince(session.startedAt) >= TimeInterval(expectedSeconds)
    }
}

struct PomodoroTaskSummary: Identifiable {
    var id: String {
        linkedMemoID.map { "memo:\($0.uuidString)" } ?? "unlinked"
    }

    let linkedMemoID: UUID?
    let taskTitle: String?
    let firstStartedAt: Date
    let durationSeconds: Int
    let sessionCount: Int
    let reflectionCount: Int
    let focusExperienceCounts: [PomodoroReflectionOptionCount]
    let progressResultCounts: [PomodoroReflectionOptionCount]
    let completedSessionID: UUID?
    let completedAt: Date?

    var displayTitle: String {
        if let taskTitle { return taskTitle }
        return linkedMemoID == nil ? "연결하지 않고 진행" : "이름을 확인할 수 없는 할 일"
    }
}

enum PomodoroTaskSummaryBuilder {
    private enum GroupKey: Hashable {
        case linked(UUID)
        case unlinked
    }

    private struct Accumulator {
        let linkedMemoID: UUID?
        let firstStartedAt: Date
        var taskTitle: String?
        var durationSeconds: Int = 0
        var sessionCount: Int = 0
        var reflectionCount: Int = 0
        var focusExperienceCounts: [String: Int] = [:]
        var progressResultCounts: [String: Int] = [:]
        var completedSessionID: UUID?
        var completedAt: Date?
    }

    static func summaries(
        sessions: [PomodoroTimeSummary],
        reflections: [PomodoroReflection],
        completions: [PomodoroTaskCompletion] = []
    ) -> [PomodoroTaskSummary] {
        let reflectionBySessionID = reflections.reduce(into: [UUID: PomodoroReflection]()) {
            $0[$1.focusSessionID] = $1
        }
        let completionBySessionID = completions.reduce(into: [UUID: PomodoroTaskCompletion]()) {
            $0[$1.focusSessionID] = $1
        }
        var accumulators: [GroupKey: Accumulator] = [:]

        for session in sessions.sorted(by: { $0.startedAt < $1.startedAt }) {
            let key = session.linkedMemoID.map(GroupKey.linked) ?? .unlinked
            var accumulator = accumulators[key] ?? Accumulator(
                linkedMemoID: session.linkedMemoID,
                firstStartedAt: session.startedAt,
                taskTitle: session.taskTitle
            )
            if let taskTitle = session.taskTitle {
                accumulator.taskTitle = taskTitle
            }
            accumulator.durationSeconds += session.durationSeconds
            accumulator.sessionCount += 1

            if let reflection = reflectionBySessionID[session.id] {
                accumulator.reflectionCount += 1
                if let focusExperience = reflection.focusExperience {
                    accumulator.focusExperienceCounts[focusExperience.rawValue, default: 0] += 1
                }
                if let progressResult = reflection.progressResult {
                    let key = progressResult == .completedAsPlanned
                        && completionBySessionID[session.id] != nil
                        ? "linked_task_completed"
                        : progressResult.rawValue
                    accumulator.progressResultCounts[key, default: 0] += 1
                }
            }
            if let completion = completionBySessionID[session.id] {
                let shouldReplaceCompletion = accumulator.completedAt.map {
                    completion.completedAt > $0
                } ?? true
                if shouldReplaceCompletion {
                    accumulator.completedSessionID = session.id
                    accumulator.completedAt = completion.completedAt
                }
            }
            accumulators[key] = accumulator
        }

        return accumulators.values
            .map { accumulator in
                let focusExperienceCounts: [PomodoroReflectionOptionCount] = {
                    var counts = PomodoroFocusExperience.allCases.compactMap { option -> PomodoroReflectionOptionCount? in
                        guard let count = accumulator.focusExperienceCounts[option.rawValue] else { return nil }
                        return PomodoroReflectionOptionCount(
                            id: option.rawValue,
                            label: option.label,
                            count: count
                        )
                    }
                    let knownCount = counts.reduce(0) { $0 + $1.count }
                    if accumulator.reflectionCount > knownCount {
                        counts.append(
                            PomodoroReflectionOptionCount(
                                id: "unknown_focus_experience",
                                label: "확인할 수 없는 응답",
                                count: accumulator.reflectionCount - knownCount
                            )
                        )
                    }
                    return counts
                }()
                let progressResultCounts: [PomodoroReflectionOptionCount] = {
                    var counts: [PomodoroReflectionOptionCount] = []
                    if let linkedCompletionCount = accumulator.progressResultCounts["linked_task_completed"] {
                        counts.append(
                            PomodoroReflectionOptionCount(
                                id: "linked_task_completed",
                                label: PomodoroProgressResult.completedAsPlanned.label(
                                    recordsLinkedTaskCompletion: true
                                ),
                                count: linkedCompletionCount
                            )
                        )
                    }
                    counts.append(contentsOf: PomodoroProgressResult.allCases.compactMap { option -> PomodoroReflectionOptionCount? in
                        guard let count = accumulator.progressResultCounts[option.rawValue] else { return nil }
                        return PomodoroReflectionOptionCount(
                            id: option.rawValue,
                            label: option.label,
                            count: count
                        )
                    })
                    let knownCount = counts.reduce(0) { $0 + $1.count }
                    if accumulator.reflectionCount > knownCount {
                        counts.append(
                            PomodoroReflectionOptionCount(
                                id: "unknown_progress_result",
                                label: "확인할 수 없는 응답",
                                count: accumulator.reflectionCount - knownCount
                            )
                        )
                    }
                    return counts
                }()

                return PomodoroTaskSummary(
                    linkedMemoID: accumulator.linkedMemoID,
                    taskTitle: accumulator.taskTitle,
                    firstStartedAt: accumulator.firstStartedAt,
                    durationSeconds: accumulator.durationSeconds,
                    sessionCount: accumulator.sessionCount,
                    reflectionCount: accumulator.reflectionCount,
                    focusExperienceCounts: focusExperienceCounts,
                    progressResultCounts: progressResultCounts,
                    completedSessionID: accumulator.completedSessionID,
                    completedAt: accumulator.completedAt
                )
            }
            .sorted { lhs, rhs in
                if (lhs.linkedMemoID == nil) != (rhs.linkedMemoID == nil) {
                    return lhs.linkedMemoID != nil
                }
                if lhs.firstStartedAt != rhs.firstStartedAt {
                    return lhs.firstStartedAt < rhs.firstStartedAt
                }
                return lhs.displayTitle < rhs.displayTitle
            }
    }
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
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let records: [AppUsageRecord]
    let viewMode: StatsViewMode
    let referenceDate: Date
    /// 선택한 날짜의 세그먼트 (일간 뷰 타임라인용). 다른 뷰모드에서는 비어 있음.
    var dailySegments: [AppUsageSegment] = []
    /// 주간 뷰에서 해당 주 7일 세그먼트. 다른 뷰모드에서는 비어 있음.
    var weekSegments: [AppUsageSegment] = []
    /// 현재 선택 기간 전체 세그먼트. 통계 집계의 우선 원천으로 사용한다.
    var periodSegments: [AppUsageSegment] = []
    /// 선택 기간에 시작한 전체 포모도로와 회고 세션의 전체 구간 행동 기록.
    var pomodoroComparisonSessions: [PomodoroSessionBreakdown] = []
    /// 현재 기간과 겹치는 타이머 세션. 전환 카운트 예외 판단에 쓰인다.
    var timerSessions: [FocusSession] = []
    /// 일간 뷰에서 포모도로 세션에 연결해 보여줄 사용자 회고.
    var pomodoroReflections: [PomodoroReflection] = []
    /// 연결한 할 일을 실제로 완료했다고 명시한 세션 근거.
    var pomodoroTaskCompletions: [PomodoroTaskCompletion] = []
    /// 휴식 후 다음 흐름 선택 기록. 주의 전환 실패 판정에서 계획된 전환/외부 업무를 제외하는 데 사용한다.
    var breakTransitionIntents: [BreakTransitionIntent] = []
    /// 주간/월간 탭에서 원본 세그먼트 재집계를 피하기 위해 부모가 넘겨주는 집계 캐시.
    var aggregateSnapshot: StatsAggregateSnapshot? = nil
    /// 하루가 지난 뒤 확정 저장된 대표 주의 상태. 과거 날짜의 상태 점에 우선 사용한다.
    var attentionDaySummaries: [AttentionDaySummary] = []

    @State private var weeklySelection: Date? = nil
    @State private var dailyAngleSelection: Double? = nil
    @State private var expandedObservationSessionIDs: Set<UUID> = []
    @State private var expandedReflectionSessionIDs: Set<UUID> = []
    @State private var editingPomodoroReflection: PomodoroReflection?
    @State private var reflectionPendingDeletion: PomodoroReflection?
    @State private var categoryStore = CategoryStore.shared
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
        .sheet(item: $editingPomodoroReflection) { reflection in
            let session = pomodoroTimeSummaries.first { $0.id == reflection.focusSessionID }
            let hasCompletion = pomodoroTaskCompletionBySessionID[reflection.focusSessionID] != nil
            let hasAvailableLinkedMemo = session?.linkedMemoID.map {
                PomodoroTaskCompletionRecorder.hasLinkedMemo(id: $0, modelContext: modelContext)
            } ?? false
            let usesLinkedTaskCompletionOption = hasCompletion
                || (hasAvailableLinkedMemo && reflection.progressResult != .completedAsPlanned)
            PomodoroReflectionEditSheet(
                reflection: reflection,
                linkedTaskTitle: session?.taskTitle,
                usesLinkedTaskCompletionOption: usesLinkedTaskCompletionOption,
                recordsLinkedTaskCompletion: hasCompletion,
                onSave: { focusExperience, progressResult, incompleteReason in
                    try updatePomodoroReflection(
                        reflection,
                        focusExperience: focusExperience,
                        progressResult: progressResult,
                        incompleteReason: incompleteReason
                    )
                },
                onCancel: {
                    editingPomodoroReflection = nil
                }
            )
        }
        .alert(
            "회고 기록을 삭제할까요?",
            isPresented: Binding(
                get: { reflectionPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        reflectionPendingDeletion = nil
                    }
                }
            ),
            presenting: reflectionPendingDeletion
        ) { reflection in
            Button("삭제", role: .destructive) {
                deletePomodoroReflection(reflection)
            }
            Button("취소", role: .cancel) {}
        } message: { reflection in
            if pomodoroTaskCompletionBySessionID[reflection.focusSessionID] != nil {
                Text("회고와 이 세션의 할 일 완료 근거를 함께 삭제합니다. 이후 다른 변경이 없었다면 할 일을 진행 중으로 되돌립니다.")
            } else {
                Text("이 기록은 개인화 데이터에서도 제외되며 되돌릴 수 없습니다.")
            }
        }
    }

    // MARK: - Daily

    private var dailyView: some View {
        VStack(alignment: .leading, spacing: 18) {
            if categoryData.isEmpty, pomodoroTimeSummaries.isEmpty {
                noDataView
            } else {
                if !categoryData.isEmpty {
                    DailyFocusSummaryCard(
                        summary: dailySummary,
                        showsDetailedMetrics: hasDailySegmentDetails
                    )

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

    private var hasDailySegmentDetails: Bool {
        dailySegments.contains {
            !Constants.hiddenLegacyCategories.contains($0.category) && $0.endTime > $0.startTime
        }
    }

    private var dailySummary: DailyFocusSummary {
        let summary: DailyFocusSummary
        if !hasDailySegmentDetails, !activeUsageRecords.isEmpty {
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
                Text(dailyObservationText(for: moment))
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func dailyObservationText(for window: DailyAttentionWindow) -> String {
        DailyAttentionObservationPresentation.windowDescription(
            primaryCategory: window.primaryCategory,
            durationText: formatDuration(window.durationSeconds),
            switches: window.switches
        )
    }

    private func dailyObservationText(for moment: DailyRecoveryMoment) -> String {
        DailyAttentionObservationPresentation.recoveryDescription(
            kind: moment.kind,
            category: moment.category,
            durationText: formatDuration(moment.durationSeconds)
        )
    }

    private var referenceMonthStart: Date {
        let calendar = Calendar.current
        return calendar.date(from: calendar.dateComponents([.year, .month], from: referenceDate))
            ?? calendar.startOfDay(for: referenceDate)
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
                    weeklyStackedChart
                    categoryLegend(data: categoryData)
                    Divider()
                    weeklyCategoryTotals
                }
            }
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

    private var weeklyStackedChart: some View {
        Chart {
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
                    .foregroundStyle(weeklyChartRuleColor)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartXScale(domain: weeklyDomain)
        .chartXAxis {
            AxisMarks(values: weeklyDays) { value in
                AxisGridLine()
                    .foregroundStyle(weeklyChartGridColor)
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        weekdayAxisLabel(date: date)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing) {
                AxisGridLine()
                    .foregroundStyle(weeklyChartGridColor)
                AxisTick()
                    .foregroundStyle(weeklyChartGridColor)
                AxisValueLabel()
                    .foregroundStyle(PopoverChrome.inkTertiary)
            }
        }
        .chartYAxisLabel("시간 (h)")
        .chartPlotStyle { plotArea in
            plotArea
                .background(weeklyChartPlotBackground)
        }
        .chartXSelection(value: $weeklySelection)
        .frame(height: 260)
        .padding(12)
        .background(weeklyChartBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(PopoverChrome.border, lineWidth: 1)
        )
    }

    private var weeklyChartBackground: Color {
        if PopoverChrome.isWineLantern {
            return PopoverChrome.card.opacity(0.88)
        }
        return Color.white.opacity(0.55)
    }

    private var weeklyChartPlotBackground: Color {
        if PopoverChrome.isWineLantern {
            return PopoverChrome.surface.opacity(0.34)
        }
        return Color.clear
    }

    private var weeklyChartGridColor: Color {
        PopoverChrome.isWineLantern ? PopoverChrome.divider.opacity(0.9) : Color.gray.opacity(0.22)
    }

    private var weeklyChartRuleColor: Color {
        PopoverChrome.isWineLantern ? PopoverChrome.accent.opacity(0.62) : Color.gray.opacity(0.35)
    }

    private func weekdayAxisLabel(date: Date) -> some View {
        Text(weekdayShortLabel(date))
            .font(.caption2)
            .foregroundStyle(PopoverChrome.inkTertiary)
            .padding(.top, 2)
    }

    private func weekdayShortLabel(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "EEE"
        return fmt.string(from: date)
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

    private var pomodoroReflectionBySessionID: [UUID: PomodoroReflection] {
        pomodoroReflections.reduce(into: [:]) { result, reflection in
            result[reflection.focusSessionID] = reflection
        }
    }

    private var pomodoroTaskCompletionBySessionID: [UUID: PomodoroTaskCompletion] {
        pomodoroTaskCompletions.reduce(into: [:]) { result, completion in
            result[completion.focusSessionID] = completion
        }
    }

    private func togglePomodoroReflection(sessionID: UUID) {
        if expandedReflectionSessionIDs.contains(sessionID) {
            expandedReflectionSessionIDs.remove(sessionID)
        } else {
            expandedReflectionSessionIDs.insert(sessionID)
        }
    }

    private func updatePomodoroReflection(
        _ reflection: PomodoroReflection,
        focusExperience: PomodoroFocusExperience,
        progressResult: PomodoroProgressResult,
        incompleteReason: PomodoroIncompleteReason?
    ) throws {
        let previousProgressResult = reflection.progressResult
        let session = timerSessions.first { $0.id == reflection.focusSessionID }
        let existingCompletion = try PomodoroTaskCompletionRecorder.completion(
            focusSessionID: reflection.focusSessionID,
            modelContext: modelContext
        )

        reflection.updateAnswers(
            focusExperience: focusExperience,
            progressResult: progressResult,
            incompleteReason: incompleteReason
        )

        do {
            var didCreateCompletion = false
            let affectedMemo: Memo?
            if let session,
               PomodoroTaskCompletionRecorder.shouldRecordCompletionOnEdit(
                   previousResult: previousProgressResult,
                   newResult: progressResult,
                   hasExistingCompletion: existingCompletion != nil
               ) {
                affectedMemo = try PomodoroTaskCompletionRecorder.recordCompletion(
                    for: session,
                    completedAt: Date(),
                    modelContext: modelContext
                )
                let recordedCompletion = try PomodoroTaskCompletionRecorder.completion(
                    focusSessionID: reflection.focusSessionID,
                    modelContext: modelContext
                )
                didCreateCompletion = existingCompletion == nil && recordedCompletion != nil
            } else if existingCompletion != nil,
                      progressResult != .completedAsPlanned {
                affectedMemo = try PomodoroTaskCompletionRecorder.removeCompletion(
                    focusSessionID: reflection.focusSessionID,
                    modelContext: modelContext
                )
            } else {
                affectedMemo = nil
            }

            try modelContext.save()
            editingPomodoroReflection = nil
            NotificationCenter.default.post(name: .pomodoroReflectionDidChange, object: nil)
            if didCreateCompletion, let linkedMemoID = session?.linkedMemoID {
                NotificationCenter.default.post(
                    name: .pomodoroLinkedTaskDidComplete,
                    object: linkedMemoID
                )
            }
            if let affectedMemo {
                PomodoroTaskCompletionRecorder.applyPostSaveEffects(
                    to: affectedMemo,
                    modelContext: modelContext
                )
            }
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func deletePomodoroReflection(_ reflection: PomodoroReflection) {
        let sessionID = reflection.focusSessionID
        reflectionPendingDeletion = nil
        do {
            let affectedMemo = try PomodoroTaskCompletionRecorder.removeCompletion(
                focusSessionID: sessionID,
                modelContext: modelContext
            )
            modelContext.delete(reflection)
            try modelContext.save()
            expandedReflectionSessionIDs.remove(sessionID)
            NotificationCenter.default.post(name: .pomodoroReflectionDidChange, object: nil)
            if let affectedMemo {
                PomodoroTaskCompletionRecorder.applyPostSaveEffects(
                    to: affectedMemo,
                    modelContext: modelContext
                )
            }
        } catch {
            modelContext.rollback()
            ToastPanel.shared.show(
                icon: "⚠️",
                title: "회고 기록을 삭제하지 못했어요",
                subtitle: "잠시 후 다시 시도해 주세요."
            )
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
        let summaries = pomodoroTimeSummaries
        let segments = activeSegments
        var firstCandidateIndex = 0

        return summaries.map { summary in
            while firstCandidateIndex < segments.count,
                  segments[firstCandidateIndex].endTime <= summary.startedAt {
                firstCandidateIndex += 1
            }
            var endIndex = firstCandidateIndex
            while endIndex < segments.count,
                  segments[endIndex].startTime < summary.endedAt {
                endIndex += 1
            }
            let overlappingSegments = Array(segments[firstCandidateIndex..<endIndex])

            return PomodoroSessionBreakdown(
                id: summary.id,
                startedAt: summary.startedAt,
                endedAt: summary.endedAt,
                category: summary.category,
                linkedMemoID: summary.linkedMemoID,
                taskTitle: summary.taskTitle,
                durationSeconds: summary.durationSeconds,
                observation: PomodoroSessionObservationBuilder.observation(
                    from: summary.startedAt,
                    to: summary.endedAt,
                    segments: overlappingSegments
                ),
                inputActivityRatio: nil,
                markerColorKey: nil
            )
        }
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
                linkedMemoID: session.linkedMemoID,
                taskTitle: session.taskTitleSnapshot,
                durationSeconds: start == session.startedAt && end == focusEnd
                    ? session.recordedFocusSeconds
                    : Int(end.timeIntervalSince(start))
            )
        }
        .sorted { $0.startedAt < $1.startedAt }
        logChartBuild("pomodoroTimeSummaries", rows: result.count, startedAt: startedAt, source: "sessions")
        return result
    }

    private var pomodoroSummaryTotalSeconds: Int {
        pomodoroTimeSummaries.reduce(0) { $0 + $1.durationSeconds }
    }

    private var pomodoroTaskSummaries: [PomodoroTaskSummary] {
        PomodoroTaskSummaryBuilder.summaries(
            sessions: pomodoroTimeSummaries,
            reflections: pomodoroReflections,
            completions: pomodoroTaskCompletions
        )
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
                        .foregroundStyle(PopoverChrome.inkTertiary)
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
                    .foregroundStyle(dayTextColor(intensity: intensity, isVacation: isVacation))
                if isVacation {
                    Text("🏖️")
                        .font(.system(size: 9))
                }
            }
            if hours > 0 {
                Text(hours >= 1 ? String(format: "%.1fh", hours) : "\(Int(round(hours * 60)))m")
                    .font(.system(size: 9))
                    .foregroundStyle(hourTextColor(intensity: intensity, isVacation: isVacation))
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
                .fill(cellFill(hours: hours, intensity: intensity, isVacation: isVacation))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(borderColor(isToday: isToday, isVacation: isVacation), lineWidth: borderWidth(isToday: isToday, isVacation: isVacation))
        )
    }

    private func borderColor(isToday: Bool, isVacation: Bool) -> Color {
        if isToday { return PopoverChrome.accent }
        if isVacation { return Color.orange.opacity(0.45) }
        return PopoverChrome.isWineLantern ? PopoverChrome.border.opacity(0.55) : Color.clear
    }

    private func borderWidth(isToday: Bool, isVacation: Bool) -> CGFloat {
        if isToday { return 1.5 }
        if isVacation { return 0.8 }
        return PopoverChrome.isWineLantern ? 0.6 : 0
    }

    private func cellFill(hours: Double, intensity: Double, isVacation: Bool) -> Color {
        if isVacation {
            return Color.orange.opacity(hours > 0 ? 0.14 + intensity * 0.18 : 0.16)
        }
        if PopoverChrome.isWineLantern {
            let opacity = hours > 0 ? 0.28 + intensity * 0.5 : 0.30
            return hours > 0 ? PopoverChrome.accent.opacity(opacity) : PopoverChrome.surfaceAlt.opacity(0.55)
        }
        return Color.accentColor.opacity(hours > 0 ? 0.2 + intensity * 0.7 : 0.06)
    }

    private func dayTextColor(intensity: Double, isVacation: Bool) -> Color {
        if PopoverChrome.isWineLantern {
            return intensity > 0.6 && !isVacation ? Color.white : PopoverChrome.ink
        }
        return intensity > 0.55 && !isVacation ? Color.white : Color.primary
    }

    private func hourTextColor(intensity: Double, isVacation: Bool) -> Color {
        if PopoverChrome.isWineLantern {
            return intensity > 0.6 && !isVacation ? Color.white.opacity(0.92) : PopoverChrome.inkSecondary
        }
        return intensity > 0.55 && !isVacation ? Color.white.opacity(0.95) : Color.secondary
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
