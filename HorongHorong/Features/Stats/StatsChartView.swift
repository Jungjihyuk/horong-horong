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
    let categorySwitchCount: Int
    let categoryTransitions: [PomodoroCategoryTransition]
    let longestContinuousAppUsage: PomodoroContinuousAppUsage?
    let apps: [PomodoroAppUsageEntry]
    let categories: [PomodoroCategoryUsageEntry]

    var hasRecords: Bool {
        recordedSeconds > 0
    }

    var attributedSeconds: Int {
        max(0, recordedSeconds - ambiguousOverlapSeconds)
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

        var appDurations: [StateKey: (appName: String, duration: TimeInterval)] = [:]
        var ambiguousOverlapDuration: TimeInterval = 0
        var userModifiedRecordedDuration: TimeInterval = 0
        var appSwitchCount = 0
        var categorySwitchCount = 0
        var transitionCounts: [TransitionKey: Int] = [:]
        var previousAttributed: (state: AttributedState, end: Date)?
        var currentRun: AttributedRun?
        var longestUsage: PomodoroContinuousAppUsage?

        func finishCurrentRun() {
            guard let currentRun else { return }
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
                    if previous.state.key.appIdentity != state.key.appIdentity {
                        appSwitchCount += 1
                    }
                    if previous.state.key.category != state.key.category {
                        categorySwitchCount += 1
                        transitionCounts[
                            TransitionKey(
                                source: previous.state.key.category,
                                target: state.key.category
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
            categories: categories
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
    let observation: PomodoroSessionObservation
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
        case .focused: return "몰입한 편"
        case .difficult: return "집중하기 어려웠던 때"
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
            let observation = session.observation
            let attributedSeconds = observation.attributedSeconds
            guard observation.sessionSeconds > 0,
                  observation.recordedSeconds > 0 else {
                missingBehaviorRecordSessionCount += 1
                continue
            }
            guard PomodoroFocusComparisonQualityPolicy.includes(observation) else {
                qualityExcludedSessionCount += 1
                continue
            }
            guard attributedSeconds > 0,
                  let longest = observation.longestContinuousAppUsage else {
                missingBehaviorRecordSessionCount += 1
                continue
            }
            if observation.ambiguousOverlapSeconds > 0 {
                sessionsWithAmbiguousRecords += 1
            }

            let denominator = Double(attributedSeconds)
            appSwitchRates.append(Double(observation.appSwitchCount) / denominator * 600)
            categorySwitchRates.append(
                Double(observation.categorySwitchCount) / denominator * 600
            )
            longestRatios.append(
                min(1, max(0, Double(longest.durationSeconds) / denominator))
            )
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
                durationSeconds: Int(end.timeIntervalSince(session.startedAt)),
                observation: PomodoroSessionObservationBuilder.observation(
                    from: session.startedAt,
                    to: end,
                    segments: overlappingSegments
                )
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
    @State private var selectedPomodoroComparisonCategory: String = ""
    @State private var selectedPomodoroComparisonTaskID: UUID?
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

    private var dailyAttentionReviewCard: some View {
        let report = dailyAttentionReport
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(DailyAttentionObservationPresentation.title(isFinalized: report.isFinalized))
                        .font(.headline)
                        .foregroundStyle(PopoverChrome.ink)
                    Text(DailyAttentionObservationPresentation.introduction(isFinalized: report.isFinalized))
                        .font(.caption)
                        .foregroundStyle(PopoverChrome.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "chart.dots.scatter")
                    Text(DailyAttentionObservationPresentation.learningStatus)
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
                        title: DailyAttentionObservationPresentation.longestWindowTitle(isFinalized: report.isFinalized),
                        window: best
                    )
                }

                if let worst = report.worstWindow {
                    dailyAttentionWindowRow(
                        icon: "waveform.path.ecg",
                        title: DailyAttentionObservationPresentation.mostSwitchedWindowTitle(isFinalized: report.isFinalized),
                        window: worst
                    )
                }

                if let quick = report.quickRecovery {
                    dailyRecoveryRow(
                        icon: "arrow.uturn.backward.circle",
                        title: "예정된 휴식 후 다시 기록된 시점",
                        moment: quick
                    )
                }

                if let difficult = report.difficultRecovery {
                    dailyRecoveryRow(
                        icon: "clock.badge.exclamationmark",
                        title: "예정된 휴식 후 대상 기록이 없던 구간",
                        moment: difficult
                    )
                }

                if !report.hasReviewSignals {
                    Text(DailyAttentionObservationPresentation.insufficientDataMessage(isFinalized: report.isFinalized))
                        .font(.caption)
                        .foregroundStyle(PopoverChrome.inkSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Divider()

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PopoverChrome.accent)
                    .frame(width: 18)
                Text(DailyAttentionObservationPresentation.learningMessage)
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
                Text(dailyObservationText(for: window))
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
                    weeklyAttentionTrendCard
                    categoryLegend(data: categoryData)
                    Divider()
                    weeklyCategoryTotals
                }

                weeklyPomodoroSection
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

    private var weeklyAttentionTrendCard: some View {
        let report = weeklyAttentionTrendReport
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("주간 기록")
                        .font(.headline)
                        .foregroundStyle(PopoverChrome.ink)
                    Text(DailyAttentionObservationPresentation.weeklySummary(
                        currentDayCount: report.currentDayCount,
                        previousDayCount: report.previousDayCount
                    ))
                        .font(.caption)
                        .foregroundStyle(PopoverChrome.inkSecondary)
                }
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "chart.dots.scatter")
                    Text(DailyAttentionObservationPresentation.learningStatus)
                        .font(.caption.bold())
                }
                .foregroundStyle(PopoverChrome.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(PopoverChrome.surfaceAlt, in: Capsule())
            }

            Divider()

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PopoverChrome.accent)
                    .frame(width: 18)
                Text(DailyAttentionObservationPresentation.learningMessage)
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .popoverCard(padding: 14)
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
                    Text("월간 기록")
                        .font(.headline)
                        .foregroundStyle(PopoverChrome.ink)
                    Text(DailyAttentionObservationPresentation.monthlySummary(
                        currentDayCount: report.currentDayCount,
                        previousDayCount: report.previousDayCount
                    ))
                        .font(.caption)
                        .foregroundStyle(PopoverChrome.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "chart.dots.scatter")
                    Text(DailyAttentionObservationPresentation.learningStatus)
                        .font(.caption.bold())
                }
                .foregroundStyle(PopoverChrome.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(PopoverChrome.surfaceAlt, in: Capsule())
            }

            Divider()

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PopoverChrome.accent)
                    .frame(width: 18)
                Text(DailyAttentionObservationPresentation.learningMessage)
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
        let sessions = pomodoroSessions
        let totalSeconds = sessions.reduce(0) { $0 + $1.durationSeconds }
        let pattern = PomodoroPatternReadModelBuilder.build(
            sessions: sessions,
            reflections: pomodoroReflections,
            completions: pomodoroTaskCompletions
        )
        let linkedTaskSummaries = pomodoroTaskSummaries.filter { $0.linkedMemoID != nil }
        let taskMetricsByMemoID = Dictionary(
            uniqueKeysWithValues: pattern.taskGroups.compactMap { group in
                group.linkedMemoID.map { ($0, group.metrics) }
            }
        )

        return Group {
            if !sessions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("포모도로 집중")
                            .font(.headline)
                            .foregroundStyle(PopoverChrome.ink)
                        Spacer()
                        Text("총 \(formatDuration(totalSeconds)) · \(sessions.count)회")
                            .font(.caption)
                            .foregroundStyle(PopoverChrome.inkSecondary)
                    }

                    pomodoroPatternOverview(pattern.general)

                    Divider()
                        .overlay(PopoverChrome.divider)

                    pomodoroFocusComparisonSection(pomodoroComparisonSessions)

                    Divider()
                        .overlay(PopoverChrome.divider)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("연결한 할 일별 기록")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PopoverChrome.inkSecondary)
                        Text("할 일이 연결되지 않은 세션은 전체·세션별 기록에 포함하고, 할 일별 기록에서만 제외했어요")
                            .font(.caption)
                            .foregroundStyle(PopoverChrome.inkTertiary)

                        if linkedTaskSummaries.isEmpty {
                            Text("할 일에 연결된 포모도로 세션이 없어요")
                                .font(.caption)
                                .foregroundStyle(PopoverChrome.inkTertiary)
                                .padding(.vertical, 6)
                        } else {
                            ForEach(linkedTaskSummaries) { summary in
                                pomodoroTaskSummaryRow(
                                    summary,
                                    patternMetrics: summary.linkedMemoID.flatMap {
                                        taskMetricsByMemoID[$0]
                                    }
                                )
                            }
                        }
                    }

                    Divider()
                        .overlay(PopoverChrome.divider)

                    Text("세션별 기록")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PopoverChrome.inkSecondary)

                    ForEach(sessions) { session in
                        pomodoroSessionRow(session)
                    }
                }
                .popoverCard(padding: 14)
            }
        }
    }

    private func pomodoroPatternOverview(_ metrics: PomodoroPatternMetrics) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("전체 포모도로 기록")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PopoverChrome.inkSecondary)

            Text(
                "할 일에 연결된 세션 \(metrics.linkedSessionCount)회 · "
                    + "연결되지 않은 세션 \(metrics.unlinkedSessionCount)회"
            )
            .font(.caption)
            .foregroundStyle(PopoverChrome.inkSecondary)
            .monospacedDigit()

            Text("회고를 작성한 세션 \(metrics.reflectionCount)/\(metrics.sessionCount)회")
                .font(.caption)
                .foregroundStyle(PopoverChrome.inkSecondary)
                .monospacedDigit()

            if metrics.sessionsWithAppRecords == 0 {
                Text("앱 사용 기록이 있는 세션이 없어 전환 횟수를 계산할 수 없어요")
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkTertiary)
            } else {
                Text(
                    "앱 사용이 기록된 세션 \(metrics.sessionsWithAppRecords)/\(metrics.sessionCount)회 · "
                        + "기록에서 확인된 앱 전환 \(metrics.appSwitchCount)회 · "
                        + "카테고리 전환 \(metrics.categorySwitchCount)회"
                )
                .font(.caption)
                .foregroundStyle(PopoverChrome.inkSecondary)
                .monospacedDigit()

                if let longest = metrics.longestContinuousAppUsage {
                    Text(
                        "가장 오래 이어진 앱 구간 · \(longest.appName) · "
                            + "\(longest.category) · \(formatDuration(longest.durationSeconds))"
                    )
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkSecondary)
                }
            }

            if metrics.sessionsWithAppRecords > 0,
               metrics.sessionsWithAppRecords < metrics.sessionCount {
                Text(
                    "앱 사용 기록이 없는 세션 "
                        + "\(metrics.sessionCount - metrics.sessionsWithAppRecords)회는 "
                        + "앱·카테고리 전환 횟수를 계산할 수 없어요"
                )
                .font(.caption)
                .foregroundStyle(PopoverChrome.inkTertiary)
            }

            if metrics.reflectionCount > 0 {
                Text("회고에서 선택한 응답")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PopoverChrome.inkTertiary)
                pomodoroReflectionCountsRow(
                    title: "몰입 경험",
                    counts: metrics.focusExperienceCounts,
                    leadingPadding: 0
                )
                pomodoroReflectionCountsRow(
                    title: "진행 결과",
                    counts: metrics.progressResultCounts,
                    leadingPadding: 0
                )
                if !metrics.incompleteReasonCounts.isEmpty {
                    pomodoroReflectionCountsRow(
                        title: "남은 이유",
                        counts: metrics.incompleteReasonCounts,
                        leadingPadding: 0
                    )
                }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            PopoverChrome.surfaceAlt.opacity(0.58),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }

    private func pomodoroTaskSummaryRow(
        _ summary: PomodoroTaskSummary,
        patternMetrics: PomodoroPatternMetrics?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "checklist")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PopoverChrome.accent)
                Text(summary.displayTitle)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(PopoverChrome.ink)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text("\(summary.sessionCount)회 · \(formatDuration(summary.durationSeconds))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: true, vertical: false)
            }

            if let completedAt = summary.completedAt {
                Label("할 일 완료 · \(timeText(completedAt)) 기록", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PopoverChrome.accent)
                    .padding(.leading, 20)
            }

            if let patternMetrics {
                if patternMetrics.sessionsWithAppRecords == 0 {
                    Text("앱 사용 기록이 있는 세션이 없어 전환 횟수를 계산할 수 없어요")
                        .font(.caption)
                        .foregroundStyle(PopoverChrome.inkTertiary)
                        .padding(.leading, 20)
                } else {
                    Text(
                        "앱 사용이 기록된 세션 "
                            + "\(patternMetrics.sessionsWithAppRecords)/\(patternMetrics.sessionCount)회 · "
                            + "기록에서 확인된 앱 전환 \(patternMetrics.appSwitchCount)회 · "
                            + "카테고리 전환 \(patternMetrics.categorySwitchCount)회"
                    )
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .monospacedDigit()
                    .padding(.leading, 20)
                }
            }

            if summary.reflectionCount == 0 {
                Text("작성된 회고 없음")
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkTertiary)
                    .padding(.leading, 20)
            } else {
                Text("회고에서 선택한 응답 \(summary.reflectionCount)/\(summary.sessionCount)회")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .padding(.leading, 20)

                pomodoroReflectionCountsRow(
                    title: "몰입 경험",
                    counts: summary.focusExperienceCounts
                )
                pomodoroReflectionCountsRow(
                    title: "진행 결과",
                    counts: summary.progressResultCounts
                )
                if let patternMetrics, !patternMetrics.incompleteReasonCounts.isEmpty {
                    pomodoroReflectionCountsRow(
                        title: "남은 이유",
                        counts: patternMetrics.incompleteReasonCounts
                    )
                }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            PopoverChrome.surfaceAlt.opacity(0.82),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }

    private func pomodoroReflectionCountsRow(
        title: String,
        counts: [PomodoroReflectionOptionCount],
        leadingPadding: CGFloat = 20
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.caption)
                .foregroundStyle(PopoverChrome.inkTertiary)
                .frame(width: 58, alignment: .leading)
            Text(counts.map { "\($0.label) \($0.count)회" }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(PopoverChrome.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.leading, leadingPadding)
    }

    private func pomodoroFocusComparisonSection(
        _ sessions: [PomodoroSessionBreakdown]
    ) -> some View {
        let categories = Array(Set(sessions.map(\.category))).sorted()
        let selectedCategory = categories.contains(selectedPomodoroComparisonCategory)
            ? selectedPomodoroComparisonCategory
            : nil
        let taskOptions = selectedCategory.map {
            PomodoroFocusComparisonBuilder.taskOptions(
                sessions: sessions,
                category: $0
            )
        } ?? []
        let taskComparisonModel = selectedCategory.map {
            PomodoroLinkedTaskComparisonBuilder.build(
                sessions: sessions,
                reflections: pomodoroReflections,
                category: $0
            )
        }
        let effectiveTaskID = selectedPomodoroComparisonTaskID.flatMap { selectedID in
            taskOptions.contains { $0.id == selectedID } ? selectedID : nil
        }
        let categorySelection = Binding<String>(
            get: { selectedCategory ?? "" },
            set: { newValue in
                selectedPomodoroComparisonCategory = newValue
                selectedPomodoroComparisonTaskID = nil
            }
        )
        let model = PomodoroFocusComparisonBuilder.build(
            sessions: sessions,
            reflections: pomodoroReflections,
            category: selectedCategory,
            linkedMemoID: effectiveTaskID
        )
        let comparedReflectionCount = model.focused.reflectionSessionCount
            + model.difficult.reflectionSessionCount
        let comparableBehaviorCount = model.focused.comparableSessionCount
            + model.difficult.comparableSessionCount

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("내 회고와 행동 기록 비교")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(PopoverChrome.ink)
                Spacer(minLength: 8)
                Text("시작한 포모도로 \(model.scopedSessionCount)회 중 회고 \(model.matchedReflectionCount)회")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .monospacedDigit()
            }

            Text("상단에서 선택한 \(viewMode.rawValue) 기간에 시작한 기록이에요. 몰입 여부를 판정하지 않고, 회고별 행동 차이만 보여드려요.")
                .font(.caption)
                .foregroundStyle(PopoverChrome.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)

            Text("가운데값에는 앱 기록 범위 80% 이상·모호한 겹침 10% 이하인 포모도로만 포함해요.")
                .font(.caption2)
                .foregroundStyle(PopoverChrome.inkTertiary)

            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("포모도로 카테고리")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                    Picker("포모도로 카테고리", selection: categorySelection) {
                        Text("전체 카테고리").tag("")
                        ForEach(categories, id: \.self) { category in
                            Text("\(Constants.categoryEmoji(for: category)) \(category)")
                                .tag(category)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 190)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("회고 자세히 보기")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                    Picker("회고 자세히 보기", selection: $selectedPomodoroComparisonTaskID) {
                        Text(selectedCategory == nil ? "카테고리를 먼저 선택" : "카테고리 전체")
                            .tag(nil as UUID?)
                        ForEach(taskOptions) { option in
                            Text(option.title).tag(Optional(option.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 260)
                    .disabled(selectedCategory == nil || taskOptions.isEmpty)
                }

                Spacer(minLength: 0)
            }

            if model.scopedSessionCount == 0 {
                Text("선택한 범위에서 시작한 포모도로가 없어요.")
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkTertiary)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if model.matchedReflectionCount == 0 {
                Text(
                    effectiveTaskID == nil
                        ? "포모도로는 있지만 작성된 종료 회고가 없어요."
                        : "이 할 일에는 작성된 종료 회고가 없어 회고별 차이를 비교할 수 없어요. 전체 행동 값은 아래 선택 카드에 그대로 표시해요."
                )
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkTertiary)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                if comparedReflectionCount == 0 {
                    Text(
                        effectiveTaskID == nil
                            ? "이 범위의 회고는 잘 모르겠음 또는 확인할 수 없는 응답만 있어 두 그룹을 비교하지 않았어요."
                            : "이 할 일의 회고는 잘 모르겠음 또는 확인할 수 없는 응답만 있어 회고별 차이를 비교하지 않았어요. 전체 행동 값은 아래 선택 카드에 그대로 표시해요."
                    )
                        .font(.caption)
                        .foregroundStyle(PopoverChrome.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 10) {
                            pomodoroFocusComparisonGroupCard(
                                model.focused,
                                model: model,
                                color: PopoverChrome.accent
                            )
                            .frame(minWidth: 280)
                            pomodoroFocusComparisonGroupCard(
                                model.difficult,
                                model: model,
                                color: PopoverChrome.inkSecondary
                            )
                            .frame(minWidth: 280)
                        }

                        VStack(spacing: 10) {
                            pomodoroFocusComparisonGroupCard(
                                model.focused,
                                model: model,
                                color: PopoverChrome.accent
                            )
                            pomodoroFocusComparisonGroupCard(
                                model.difficult,
                                model: model,
                                color: PopoverChrome.inkSecondary
                            )
                        }
                    }
                }

                HStack(spacing: 12) {
                    if model.unsure.reflectionSessionCount > 0 {
                        Label(
                            "잘 모르겠음 \(model.unsure.reflectionSessionCount)회 · 비교 그룹과 분리",
                            systemImage: "questionmark.circle"
                        )
                    }
                    if model.unknownReflectionCount > 0 {
                        Label(
                            "확인할 수 없는 응답 \(model.unknownReflectionCount)회",
                            systemImage: "exclamationmark.circle"
                        )
                    }
                }
                .font(.caption)
                .foregroundStyle(PopoverChrome.inkTertiary)

                if comparableBehaviorCount > 0 {
                    Text("비교 가능한 포모도로가 한 번이면 점이 그 기록값이에요. 여러 번이면 큰 점이 가운데값이고, 색 선의 양 끝이 가장 낮고 높은 값이에요.")
                        .font(.caption2)
                        .foregroundStyle(PopoverChrome.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("전환 0회는 서로 이어진 앱 기록 사이에서 변화가 확인되지 않았다는 뜻이에요. 기록이 비거나 겹친 뒤의 변화는 세지 않아요. 이어진 비율 100%는 겹친 시간을 제외하고 명확히 확인된 앱 기록 전체가 한 앱·카테고리로 이어졌다는 뜻이에요.")
                        .font(.caption2)
                        .foregroundStyle(PopoverChrome.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()
                .overlay(PopoverChrome.divider)

            pomodoroLinkedTaskComparisonSection(taskComparisonModel)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            PopoverChrome.surfaceAlt.opacity(0.58),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .onChange(of: categories) { _, availableCategories in
            guard !selectedPomodoroComparisonCategory.isEmpty,
                  !availableCategories.contains(selectedPomodoroComparisonCategory) else {
                return
            }
            selectedPomodoroComparisonCategory = ""
            selectedPomodoroComparisonTaskID = nil
        }
        .onChange(of: taskOptions.map(\.id)) { _, availableTaskIDs in
            guard let selectedPomodoroComparisonTaskID,
                  !availableTaskIDs.contains(selectedPomodoroComparisonTaskID) else {
                return
            }
            self.selectedPomodoroComparisonTaskID = nil
        }
    }

    @ViewBuilder
    private func pomodoroLinkedTaskComparisonSection(
        _ model: PomodoroLinkedTaskComparisonReadModel?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("할 일별 행동 기록 비교")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                Spacer(minLength: 8)
                if let model {
                    Text("\(model.items.count)개")
                        .font(.caption)
                        .foregroundStyle(PopoverChrome.inkTertiary)
                        .monospacedDigit()
                }
            }

            if let model {
                Text("\(Constants.categoryEmoji(for: model.category)) \(model.category)에서 연결한 할 일을 같은 눈금으로 보여드려요. 카드 순서는 값의 높고 낮음과 관계없어요.")
                    .font(.caption2)
                    .foregroundStyle(PopoverChrome.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                if !model.items.isEmpty {
                    Text("회/10분은 비거나 겹친 시간을 뺀, 앱·카테고리가 명확한 기록 10분당 전환 횟수예요.")
                        .font(.caption2)
                        .foregroundStyle(PopoverChrome.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                switch model.items.count {
                case 0:
                    Text("선택한 기간의 이 카테고리에는 할 일이 연결된 포모도로가 없어요.")
                        .font(.caption)
                        .foregroundStyle(PopoverChrome.inkTertiary)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .center)
                case 1:
                    Text("선택한 기간에는 연결된 할 일이 1개예요. 다른 할 일에 포모도로를 연결하면 나란히 비교할 수 있어요.")
                        .font(.caption)
                        .foregroundStyle(PopoverChrome.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let item = model.items.first {
                        pomodoroLinkedTaskComparisonCard(item, model: model)
                    }
                default:
                    let comparableTaskCount = model.items.filter {
                        $0.behavior.comparableSessionCount > 0
                    }.count
                    let columns = dynamicTypeSize.isAccessibilitySize
                        ? [GridItem(.flexible(), spacing: 10)]
                        : [GridItem(.adaptive(minimum: 300), spacing: 10)]

                    if comparableTaskCount < 2 {
                        Text("행동 값을 계산할 수 있는 할 일이 \(comparableTaskCount)개라 아직 행동 차이를 나란히 비교하기 어려워요.")
                            .font(.caption)
                            .foregroundStyle(PopoverChrome.inkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                        ForEach(model.items) { item in
                            pomodoroLinkedTaskComparisonCard(item, model: model)
                        }
                    }

                }

                if !model.items.isEmpty {
                    Text("행동 값은 연결한 모든 포모도로 중 기록 기준을 충족한 세션으로 계산하고, 회고 수는 따로 보여드려요. 점 하나는 한 세션의 값이며 반복된 경향은 아니에요. 여러 세션이면 큰 점은 가운데값, 선 양 끝은 최솟값과 최댓값이에요.")
                        .font(.caption2)
                        .foregroundStyle(PopoverChrome.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("카드의 ‘자세히’를 누르면 위 영역에서 회고별 행동 차이를 봐요. 회고 여부와 무관한 전체 행동 값은 카드에 그대로 남아요.")
                        .font(.caption2)
                        .foregroundStyle(PopoverChrome.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("먼저 카테고리를 선택해 주세요. 선택한 기간·카테고리 안에서 연결한 할 일을 비교해요.")
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkTertiary)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private func pomodoroLinkedTaskComparisonCard(
        _ item: PomodoroLinkedTaskComparisonItem,
        model: PomodoroLinkedTaskComparisonReadModel
    ) -> some View {
        let reflection = item.reflections
        let behavior = item.behavior
        let isSelected = selectedPomodoroComparisonTaskID == item.id
        let titleLineLimit: Int? = dynamicTypeSize.isAccessibilitySize ? nil : 2
        var reflectionParts = [
            "몰입한 편 \(reflection.focusedCount)회",
            "집중하기 어려웠던 때 \(reflection.difficultCount)회",
            "잘 모르겠음 \(reflection.unsureCount)회",
        ]
        if reflection.unknownCount > 0 {
            reflectionParts.append("확인 불가 \(reflection.unknownCount)회")
        }
        var recordParts: [String] = []
        if behavior.missingBehaviorRecordSessionCount > 0 {
            recordParts.append("앱 기록 없음 \(behavior.missingBehaviorRecordSessionCount)회")
        }
        if behavior.qualityExcludedSessionCount > 0 {
            recordParts.append(
                "기록 범위·겹침 기준 밖 \(behavior.qualityExcludedSessionCount)회"
            )
        }
        if behavior.sessionsWithAmbiguousRecords > 0 {
            recordParts.append(
                "겹친 시간을 빼고 계산한 세션 \(behavior.sessionsWithAmbiguousRecords)회"
            )
        }

        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 6) {
                Text(item.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PopoverChrome.ink)
                    .lineLimit(titleLineLimit)
                    .help(item.title)
                Spacer(minLength: 4)
                Button {
                    selectedPomodoroComparisonTaskID = item.id
                } label: {
                    Label(
                        isSelected ? "보는 중" : "자세히",
                        systemImage: isSelected ? "checkmark.circle.fill" : "chevron.up"
                    )
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(
                        isSelected ? PopoverChrome.accent : PopoverChrome.inkTertiary
                    )
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
                .help("\(item.title) 회고별 행동 차이 자세히 보기")
                .accessibilityHint("위 비교 영역에서 이 할 일의 회고별 행동 차이를 봅니다")
                .accessibilityValue(isSelected ? "자세히 보는 중" : "선택하지 않음")
            }

            if isSelected {
                Text("위 회고별 비교에서 자세히 보는 중")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(PopoverChrome.accent)
            }

            Text("포모도로 \(item.totalSessionCount)회 · \(formatDuration(item.totalDurationSeconds))")
                .font(.caption)
                .foregroundStyle(PopoverChrome.inkSecondary)
                .monospacedDigit()

            Text("회고 작성 \(reflection.answeredCount)/\(item.totalSessionCount)회 · 행동 값을 계산한 세션 \(behavior.comparableSessionCount)/\(item.totalSessionCount)회")
                .font(.caption2)
                .foregroundStyle(PopoverChrome.inkSecondary)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)

            Text(reflectionParts.joined(separator: " · "))
                .font(.caption2)
                .foregroundStyle(PopoverChrome.inkTertiary)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)

            if !recordParts.isEmpty {
                Text(recordParts.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(PopoverChrome.inkTertiary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }

            if behavior.comparableSessionCount == 0 {
                Text("현재 기준으로 계산할 행동 기록이 없어요.")
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkTertiary)
                    .padding(.vertical, 6)
            } else {
                pomodoroFocusComparisonMetric(
                    title: "확인된 앱 전환",
                    medianValue: behavior.medianAppSwitchesPerAttributedTenMinutes ?? 0,
                    medianText: comparisonRateText(
                        behavior.medianAppSwitchesPerAttributedTenMinutes
                    ),
                    values: behavior.appSwitchesPerAttributedTenMinutes,
                    upperBound: model.appSwitchDomainMaximum,
                    upperBoundText: comparisonRateAxisText(model.appSwitchDomainMaximum),
                    color: PopoverChrome.accent,
                    groupLabel: "\(item.title) 할 일",
                    formatsAsRatio: false
                )
                pomodoroFocusComparisonMetric(
                    title: "확인된 카테고리 전환",
                    medianValue: behavior.medianCategorySwitchesPerAttributedTenMinutes ?? 0,
                    medianText: comparisonRateText(
                        behavior.medianCategorySwitchesPerAttributedTenMinutes
                    ),
                    values: behavior.categorySwitchesPerAttributedTenMinutes,
                    upperBound: model.categorySwitchDomainMaximum,
                    upperBoundText: comparisonRateAxisText(
                        model.categorySwitchDomainMaximum
                    ),
                    color: PopoverChrome.accent,
                    groupLabel: "\(item.title) 할 일",
                    formatsAsRatio: false
                )
                pomodoroFocusComparisonMetric(
                    title: "한 앱·카테고리로 가장 길게 이어진 비율",
                    medianValue: behavior.medianLongestContinuousAppCategoryRatio ?? 0,
                    medianText: comparisonRatioText(
                        behavior.medianLongestContinuousAppCategoryRatio
                    ),
                    values: behavior.longestContinuousAppCategoryRatios,
                    upperBound: 1,
                    upperBoundText: "100%",
                    color: PopoverChrome.accent,
                    groupLabel: "\(item.title) 할 일",
                    formatsAsRatio: true
                )
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            PopoverChrome.card.opacity(0.72),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(
                    isSelected ? PopoverChrome.accent.opacity(0.72) : PopoverChrome.divider,
                    lineWidth: isSelected ? 1.5 : 1
                )
        )
        .accessibilityElement(children: .contain)
    }

    private func pomodoroFocusComparisonGroupCard(
        _ metrics: PomodoroFocusComparisonMetrics,
        model: PomodoroFocusComparisonReadModel,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(metrics.group.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PopoverChrome.ink)
                Spacer(minLength: 6)
                Text("\(metrics.reflectionSessionCount)회")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .monospacedDigit()
            }

            if metrics.reflectionSessionCount == 0 {
                Text("이 범위에서 선택한 회고가 없어요")
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkTertiary)
                    .padding(.vertical, 10)
            } else {
                Text(
                    "행동 기록 \(metrics.comparableSessionCount)/\(metrics.reflectionSessionCount)회"
                )
                .font(.caption)
                .foregroundStyle(PopoverChrome.inkSecondary)
                .monospacedDigit()

                if metrics.missingBehaviorRecordSessionCount > 0 {
                    Text("비교할 앱 기록 없음 \(metrics.missingBehaviorRecordSessionCount)회")
                        .font(.caption2)
                        .foregroundStyle(PopoverChrome.inkTertiary)
                }
                if metrics.qualityExcludedSessionCount > 0 {
                    Text("기록 범위·겹침 기준 밖 \(metrics.qualityExcludedSessionCount)회")
                        .font(.caption2)
                        .foregroundStyle(PopoverChrome.inkTertiary)
                }
                if metrics.sessionsWithAmbiguousRecords > 0 {
                    Text("겹친 시간은 빼고 계산한 포모도로 \(metrics.sessionsWithAmbiguousRecords)회")
                        .font(.caption2)
                        .foregroundStyle(PopoverChrome.inkTertiary)
                }

                if metrics.comparableSessionCount == 0 {
                    Text("현재 기준으로 가운데값을 계산할 수 있는 포모도로가 없어요")
                        .font(.caption)
                        .foregroundStyle(PopoverChrome.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 6)
                } else {
                    pomodoroFocusComparisonMetric(
                        title: "확인된 앱 전환",
                        medianValue: metrics.medianAppSwitchesPerAttributedTenMinutes ?? 0,
                        medianText: comparisonRateText(
                            metrics.medianAppSwitchesPerAttributedTenMinutes
                        ),
                        values: metrics.appSwitchesPerAttributedTenMinutes,
                        upperBound: model.appSwitchDomainMaximum,
                        upperBoundText: comparisonRateAxisText(model.appSwitchDomainMaximum),
                        color: color,
                        groupLabel: metrics.group.label,
                        formatsAsRatio: false
                    )
                    pomodoroFocusComparisonMetric(
                        title: "확인된 카테고리 전환",
                        medianValue: metrics.medianCategorySwitchesPerAttributedTenMinutes ?? 0,
                        medianText: comparisonRateText(
                            metrics.medianCategorySwitchesPerAttributedTenMinutes
                        ),
                        values: metrics.categorySwitchesPerAttributedTenMinutes,
                        upperBound: model.categorySwitchDomainMaximum,
                        upperBoundText: comparisonRateAxisText(model.categorySwitchDomainMaximum),
                        color: color,
                        groupLabel: metrics.group.label,
                        formatsAsRatio: false
                    )
                    pomodoroFocusComparisonMetric(
                        title: "한 앱·카테고리로 가장 길게 이어진 비율",
                        medianValue: metrics.medianLongestContinuousAppCategoryRatio ?? 0,
                        medianText: comparisonRatioText(
                            metrics.medianLongestContinuousAppCategoryRatio
                        ),
                        values: metrics.longestContinuousAppCategoryRatios,
                        upperBound: 1,
                        upperBoundText: "100%",
                        color: color,
                        groupLabel: metrics.group.label,
                        formatsAsRatio: true
                    )
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            PopoverChrome.card.opacity(0.72),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
    }

    private func pomodoroFocusComparisonMetric(
        title: String,
        medianValue: Double,
        medianText: String,
        values: [Double],
        upperBound: Double,
        upperBoundText: String,
        color: Color,
        groupLabel: String,
        formatsAsRatio: Bool
    ) -> some View {
        let minimumText = comparisonMetricValueText(values.min(), asRatio: formatsAsRatio)
        let maximumText = comparisonMetricValueText(values.max(), asRatio: formatsAsRatio)

        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(PopoverChrome.inkTertiary)
                    .lineLimit(2)
                Spacer(minLength: 4)
                Text("\(values.count == 1 ? "이번 기록" : "가운데값") \(medianText)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(PopoverChrome.inkSecondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: true, vertical: false)
            }

            pomodoroFocusComparisonDistribution(
                title: title,
                values: values,
                medianValue: medianValue,
                upperBound: upperBound,
                color: color,
                groupLabel: groupLabel,
                minimumText: minimumText,
                medianText: medianText,
                maximumText: maximumText
            )

            HStack {
                Text("0")
                Spacer()
                Text(upperBoundText)
            }
            .font(.caption2)
            .foregroundStyle(PopoverChrome.inkTertiary)
            .monospacedDigit()
        }
        .padding(.top, 2)
    }

    private func pomodoroFocusComparisonDistribution(
        title: String,
        values: [Double],
        medianValue: Double,
        upperBound: Double,
        color: Color,
        groupLabel: String,
        minimumText: String,
        medianText: String,
        maximumText: String
    ) -> some View {
        let minimum = values.min() ?? medianValue
        let maximum = values.max() ?? medianValue
        let safeUpperBound = max(upperBound, 0.0001)

        return GeometryReader { geometry in
            let inset: CGFloat = 5
            let availableWidth = max(0, geometry.size.width - inset * 2)
            let minimumX = inset + availableWidth * min(1, max(0, minimum / safeUpperBound))
            let maximumX = inset + availableWidth * min(1, max(0, maximum / safeUpperBound))
            let medianX = inset + availableWidth * min(1, max(0, medianValue / safeUpperBound))
            let centerY = geometry.size.height / 2

            ZStack {
                Capsule()
                    .fill(PopoverChrome.divider)
                    .frame(height: 2)
                    .position(x: geometry.size.width / 2, y: centerY)

                if values.count > 1 {
                    Capsule()
                        .fill(color.opacity(0.42))
                        .frame(width: max(2, maximumX - minimumX), height: 5)
                        .position(x: (minimumX + maximumX) / 2, y: centerY)

                    Circle()
                        .fill(color.opacity(0.72))
                        .frame(width: 5, height: 5)
                        .position(x: minimumX, y: centerY)

                    Circle()
                        .fill(color.opacity(0.72))
                        .frame(width: 5, height: 5)
                        .position(x: maximumX, y: centerY)
                }

                Circle()
                    .fill(color)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(PopoverChrome.card, lineWidth: 1))
                    .position(x: medianX, y: centerY)
            }
        }
        .frame(height: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(groupLabel), \(title) 값 위치")
        .accessibilityValue(
            values.count == 1
                ? "이번 기록 \(medianText)"
                : "포모도로 \(values.count)회, 최솟값 \(minimumText), 가운데값 \(medianText), 최댓값 \(maximumText)"
        )
    }

    private func comparisonRateText(_ value: Double?) -> String {
        guard let value else { return "-" }
        return "\(String(format: "%.1f", value))회/10분"
    }

    private func comparisonRateAxisText(_ value: Double) -> String {
        "\(String(format: "%.1f", value))회/10분"
    }

    private func comparisonRatioText(_ value: Double?) -> String {
        guard let value else { return "-" }
        return "\(Int((value * 100).rounded()))%"
    }

    private func comparisonMetricValueText(_ value: Double?, asRatio: Bool) -> String {
        asRatio ? comparisonRatioText(value) : comparisonRateText(value)
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

                    Divider()
                        .overlay(PopoverChrome.divider)

                    pomodoroFocusComparisonSection(pomodoroComparisonSessions)
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

                    Divider()
                        .overlay(PopoverChrome.divider)

                    pomodoroFocusComparisonSection(pomodoroComparisonSessions)
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

                if session.linkedMemoID != nil {
                    pomodoroTaskContext(session)
                        .padding(.leading, 22)
                }

                pomodoroObservation(session.observation, sessionID: session.id)
                    .padding(.leading, 22)

                if let reflection = pomodoroReflectionBySessionID[session.id] {
                    pomodoroReflectionSummary(reflection, sessionID: session.id)
                        .padding(.leading, 22)
                        .padding(.top, 4)
                }
            }
            .padding(.vertical, 6)
            Divider()
        }
    }

    private func pomodoroObservation(
        _ observation: PomodoroSessionObservation,
        sessionID: UUID
    ) -> some View {
        let isExpanded = expandedObservationSessionIDs.contains(sessionID)

        return VStack(alignment: .leading, spacing: 8) {
            Button {
                guard observation.hasRecords else { return }
                togglePomodoroObservation(sessionID: sessionID)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "eye.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PopoverChrome.accent)
                    Text("객관적 관찰")
                        .font(.caption.bold())
                        .foregroundStyle(PopoverChrome.ink)
                    Text("·")
                        .foregroundStyle(PopoverChrome.inkTertiary)
                    Text(observationSummary(observation))
                        .font(.caption)
                        .foregroundStyle(PopoverChrome.inkSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if observation.hasRecords {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(PopoverChrome.inkTertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if observation.hasRecords && isExpanded {
                Divider()
                    .overlay(PopoverChrome.divider)

                Text("3초 미만의 측정 간격은 이어진 기록으로 보고, 그보다 긴 공백과 겹침은 전환에서 제외해요. 브라우저 카테고리는 기록 시점 기준이에요.")
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkTertiary)

                HStack(spacing: 12) {
                    Label(
                        "기록 \(formatDuration(observation.recordedSeconds)) / \(formatDuration(observation.sessionSeconds))",
                        systemImage: "clock"
                    )
                    Label(
                        "기록상 앱 전환 \(observation.appSwitchCount)회",
                        systemImage: "arrow.left.arrow.right"
                    )
                    Label(
                        "기록상 카테고리 전환 \(observation.categorySwitchCount)회",
                        systemImage: "square.grid.2x2"
                    )
                }
                .font(.caption)
                .foregroundStyle(PopoverChrome.inkSecondary)

                if observation.unrecordedSeconds > 0 {
                    Label(
                        "앱 사용 미기록 \(formatDuration(observation.unrecordedSeconds))",
                        systemImage: "eye.slash"
                    )
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkTertiary)
                }

                if observation.ambiguousOverlapSeconds > 0 {
                    Label(
                        "겹쳐서 앱을 특정하지 못한 기록 \(formatDuration(observation.ambiguousOverlapSeconds))",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkTertiary)
                }

                if observation.userModifiedRecordedSeconds > 0 {
                    Label(
                        "사용자가 추가하거나 수정한 기록 \(formatDuration(observation.userModifiedRecordedSeconds)) 포함",
                        systemImage: "pencil"
                    )
                    .font(.caption)
                    .foregroundStyle(PopoverChrome.inkTertiary)
                }

                if let longest = observation.longestContinuousAppUsage {
                    pomodoroObservationFactRow(
                        title: "가장 긴 연속 앱 구간",
                        value: "\(longest.appName) · \(longest.category) · \(formatDuration(longest.durationSeconds))"
                    )
                }

                if !observation.categories.isEmpty {
                    pomodoroObservationFactRow(
                        title: "카테고리별",
                        value: observation.categories
                            .map { "\($0.category) \(formatDuration($0.durationSeconds))" }
                            .joined(separator: " · ")
                    )
                }

                if !observation.categoryTransitions.isEmpty {
                    pomodoroObservationFactRow(
                        title: "기록상 전환 경로",
                        value: observation.categoryTransitions
                            .map { "\($0.source) → \($0.target) \($0.count)회" }
                            .joined(separator: " · ")
                    )
                }

                if !observation.apps.isEmpty {
                    Divider()
                        .overlay(PopoverChrome.divider)

                    ForEach(observation.apps) { app in
                        HStack(spacing: 6) {
                            Text(app.appName)
                                .font(.callout)
                                .foregroundStyle(PopoverChrome.inkSecondary)
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
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            PopoverChrome.surfaceAlt.opacity(0.58),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
    }

    private func observationSummary(_ observation: PomodoroSessionObservation) -> String {
        guard observation.hasRecords else { return "세션 중 기록된 앱 사용이 없어요" }
        var parts = [
            "기록 \(formatDuration(observation.recordedSeconds))/\(formatDuration(observation.sessionSeconds))",
            "기록상 앱 전환 \(observation.appSwitchCount)회",
        ]
        if observation.ambiguousOverlapSeconds > 0 {
            parts.append("겹침 있음")
        }
        if observation.userModifiedRecordedSeconds > 0 {
            parts.append("사용자 변경 포함")
        }
        return parts.joined(separator: " · ")
    }

    private func togglePomodoroObservation(sessionID: UUID) {
        if expandedObservationSessionIDs.contains(sessionID) {
            expandedObservationSessionIDs.remove(sessionID)
        } else {
            expandedObservationSessionIDs.insert(sessionID)
        }
    }

    private func pomodoroObservationFactRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(PopoverChrome.inkTertiary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PopoverChrome.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func pomodoroTaskContext(_ session: PomodoroSessionBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(session.taskTitle ?? "이름을 확인할 수 없는 할 일", systemImage: "checklist")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PopoverChrome.ink)
                .lineLimit(2)

            if pomodoroTaskCompletionBySessionID[session.id] != nil {
                Label("이 세션에서 할 일을 완료했어요", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PopoverChrome.accent)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            PopoverChrome.surfaceAlt.opacity(0.82),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
    }

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

    private func pomodoroReflectionSummary(
        _ reflection: PomodoroReflection,
        sessionID: UUID
    ) -> some View {
        let isExpanded = expandedReflectionSessionIDs.contains(sessionID)
        let focusLabel = reflection.focusExperience?.label ?? "확인할 수 없는 몰입 경험"
        let recordsLinkedTaskCompletion = pomodoroTaskCompletionBySessionID[sessionID] != nil
        let progressLabel = reflection.progressResult?.label(
            recordsLinkedTaskCompletion: recordsLinkedTaskCompletion
        ) ?? "확인할 수 없는 진행 결과"

        return VStack(alignment: .leading, spacing: 9) {
            Button {
                togglePomodoroReflection(sessionID: sessionID)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "quote.bubble.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PopoverChrome.accent)
                    Text("나의 회고")
                        .font(.caption.bold())
                        .foregroundStyle(PopoverChrome.ink)
                    Text("·")
                        .foregroundStyle(PopoverChrome.inkTertiary)
                    Text(focusLabel)
                        .font(.caption)
                        .foregroundStyle(PopoverChrome.inkSecondary)
                        .lineLimit(1)
                    Text("·")
                        .foregroundStyle(PopoverChrome.inkTertiary)
                    Text(progressLabel)
                        .font(.caption)
                        .foregroundStyle(PopoverChrome.inkSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(PopoverChrome.inkTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()

                VStack(alignment: .leading, spacing: 7) {
                    pomodoroReflectionAnswerRow(title: "몰입 경험", value: focusLabel)
                    pomodoroReflectionAnswerRow(title: "진행 결과", value: progressLabel)

                    if reflection.progressResult?.requiresReason == true || reflection.incompleteReason != nil {
                        pomodoroReflectionAnswerRow(
                            title: "가장 큰 이유",
                            value: reflection.incompleteReason?.label ?? "이유가 기록되지 않았어요"
                        )
                    }
                }

                HStack(spacing: 8) {
                    Spacer()
                    Button("수정") {
                        editingPomodoroReflection = reflection
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("삭제", role: .destructive) {
                        reflectionPendingDeletion = reflection
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            PopoverChrome.accentSoft.opacity(0.24),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(PopoverChrome.border, lineWidth: 1)
        )
    }

    private func pomodoroReflectionAnswerRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.caption)
                .foregroundStyle(PopoverChrome.inkTertiary)
                .frame(width: 74, alignment: .leading)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PopoverChrome.ink)
            Spacer(minLength: 0)
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
                )
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
