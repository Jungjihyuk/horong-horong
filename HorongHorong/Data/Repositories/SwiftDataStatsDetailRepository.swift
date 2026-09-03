import Foundation
import SwiftData
import OSLog

@MainActor
final class SwiftDataStatsDetailRepository: StatsDetailRepository {
    private let context: ModelContext

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "app.horonghorong",
        category: "StatsDetailRepository"
    )

    init(context: ModelContext) {
        self.context = context
    }

    func loadDetailSnapshot(
        mode: StatsViewMode,
        startDate: Date,
        endDate: Date,
        selectedDate: Date
    ) -> StatsDetailSnapshot {
        let loadStartedAt = Date()
        Self.logger.notice("StatsDetailRepository load start mode=\(mode.rawValue, privacy: .public) start=\(Int(startDate.timeIntervalSince1970)) end=\(Int(endDate.timeIntervalSince1970))")

        // 1. AppUsageRecord
        let recordsDescriptor = FetchDescriptor<AppUsageRecord>(
            predicate: #Predicate { $0.date >= startDate && $0.date < endDate },
            sortBy: [SortDescriptor(\.date)]
        )
        let fetchedRecords = (try? context.fetch(recordsDescriptor)) ?? []

        // 2. TimerSessions (FocusSession)
        let fetchedSessions = loadTimerSessions(start: startDate, end: endDate)

        // 3. PomodoroReflections
        let fetchedPomodoroReflections = loadPomodoroReflections(for: fetchedSessions)

        // 4. PomodoroTaskCompletions
        let fetchedPomodoroTaskCompletions = loadPomodoroTaskCompletions(for: fetchedSessions)

        // 5. BreakTransitionIntents
        let fetchedBreakTransitions = loadBreakTransitionIntents(start: startDate, end: endDate)

        // 6. AttentionDaySummary
        let attentionSummaryStart = attentionSummaryLoadStart(for: mode, start: startDate)
        let finalizedAttentionDays = AttentionDaySummaryRecorder.finalizeCompletedDays(
            from: attentionSummaryStart,
            to: endDate,
            modelContext: context
        )

        // 7. StatsAggregateSnapshot
        let aggregate = loadAggregateSnapshot(
            for: mode,
            start: startDate,
            end: endDate,
            records: fetchedRecords,
            timerSessions: fetchedSessions
        )

        // 8. Segments
        let loadedSegments = loadSegments(
            for: mode,
            start: startDate,
            end: endDate,
            records: fetchedRecords,
            timerSessions: fetchedSessions,
            aggregateSnapshot: aggregate
        )

        // 9. Pomodoro Comparison
        let includedPomodoroSessionIDs = Set(fetchedSessions.map(\.id))
        let loadedPomodoroSegments = loadPomodoroSegments(
            for: fetchedSessions,
            includedSessionIDs: includedPomodoroSessionIDs,
            availablePeriodSegments: loadedSegments.period,
            periodSegmentsCoverFullRange: periodSegmentsCoverFullRange(
                mode: mode,
                records: fetchedRecords,
                aggregateSnapshot: aggregate
            ),
            periodStart: startDate,
            periodEnd: endDate
        )
        let loadedPomodoroComparisonSessions = PomodoroComparisonPeriodBuilder.build(
            sessions: fetchedSessions,
            segments: loadedPomodoroSegments,
            periodStart: startDate,
            periodEnd: endDate
        )

        // DTO 매핑
        let recordDTOs = fetchedRecords.map {
            StatsAppUsageRecord(
                id: $0.id,
                appName: $0.appName,
                bundleIdentifier: $0.bundleIdentifier,
                category: $0.category,
                date: $0.date,
                durationSeconds: $0.durationSeconds
            )
        }

        let dailySegmentDTOs = loadedSegments.daily.map(Self.toSegmentDTO)
        let weekSegmentDTOs = loadedSegments.week.map(Self.toSegmentDTO)
        let periodSegmentDTOs = loadedSegments.period.map(Self.toSegmentDTO)

        let sessionDTOs = fetchedSessions.map {
            StatsFocusSession(
                id: $0.id,
                startedAt: $0.startedAt,
                endedAt: $0.endedAt,
                category: $0.category,
                markerColorKey: $0.markerColorKey,
                taskTitleSnapshot: $0.taskTitleSnapshot,
                linkedMemoID: $0.linkedMemoID,
                focusMinutes: $0.focusMinutes,
                recordedFocusSeconds: $0.recordedFocusSeconds,
                completed: $0.completed
            )
        }

        let reflectionDTOs = fetchedPomodoroReflections.map {
            StatsPomodoroReflection(
                id: $0.id,
                focusSessionID: $0.focusSessionID,
                focusExperienceRawValue: $0.focusExperienceRawValue,
                progressResultRawValue: $0.progressResultRawValue,
                incompleteReasonRawValue: $0.incompleteReasonRawValue,
                answeredAt: $0.answeredAt
            )
        }

        let completionDTOs = fetchedPomodoroTaskCompletions.map {
            StatsPomodoroTaskCompletion(
                id: $0.id,
                focusSessionID: $0.focusSessionID,
                linkedMemoID: $0.linkedMemoID,
                taskTitleSnapshot: $0.taskTitleSnapshot,
                completedAt: $0.completedAt
            )
        }

        let breakIntentDTOs = fetchedBreakTransitions.map {
            StatsBreakTransitionIntent(
                id: $0.id,
                breakEndedAt: $0.breakEndedAt,
                decidedAt: $0.decidedAt,
                decisionRawValue: $0.decisionRawValue,
                previousCategory: $0.previousCategory,
                nextCategory: $0.nextCategory
            )
        }

        let attentionDayDTOs = finalizedAttentionDays.map {
            StatsAttentionDaySummary(
                id: $0.id,
                day: $0.day,
                dayKey: $0.dayKey,
                overallScore: $0.overallScore,
                flowState: $0.flowState,
                selectiveEventCount: $0.selectiveEventCount,
                sustainedEventCount: $0.sustainedEventCount,
                returnEventCount: $0.returnEventCount,
                representativeReason: $0.representativeReason
            )
        }

        let elapsedMs = Int(Date().timeIntervalSince(loadStartedAt) * 1_000)
        Self.logger.notice("StatsDetailRepository loaded mode=\(mode.rawValue, privacy: .public) elapsed=\(elapsedMs)ms")

        return StatsDetailSnapshot(
            records: recordDTOs,
            dailySegments: dailySegmentDTOs,
            weekSegments: weekSegmentDTOs,
            periodSegments: periodSegmentDTOs,
            pomodoroComparisonSessions: loadedPomodoroComparisonSessions,
            timerSessions: sessionDTOs,
            pomodoroReflections: reflectionDTOs,
            pomodoroTaskCompletions: completionDTOs,
            breakTransitionIntents: breakIntentDTOs,
            aggregateSnapshot: aggregate,
            attentionDaySummaries: attentionDayDTOs
        )
    }

    private static func toSegmentDTO(_ segment: AppUsageSegment) -> StatsAppUsageSegment {
        StatsAppUsageSegment(
            id: segment.id,
            appName: segment.appName,
            bundleIdentifier: segment.bundleIdentifier,
            category: segment.category,
            startTime: segment.startTime,
            endTime: segment.endTime,
            isManual: segment.isManual,
            isUserModified: segment.isUserModified
        )
    }

    func refreshFocusCards(
        mode: StatsViewMode,
        selectedDate: Date
    ) -> (nudge: FocusNudgeSnapshot?, trend: HistoricalFocusTrendSnapshot?) {
        guard mode == .daily else {
            return (nil, nil)
        }

        let calendar = Calendar.current
        if calendar.isDateInToday(selectedDate) {
            let nudge = FocusNudgeSnapshot.make(
                day: selectedDate,
                modelContext: context
            )
            return (nudge, nil)
        } else if calendar.startOfDay(for: selectedDate) < calendar.startOfDay(for: Date()) {
            let trend = HistoricalFocusTrendSnapshot.make(
                day: selectedDate,
                modelContext: context
            )
            return (nil, trend)
        } else {
            return (nil, nil)
        }
    }

    func invalidateAggregateCaches(containing date: Date) {
        let descriptor = FetchDescriptor<StatsAggregateCache>()
        let caches = (try? context.fetch(descriptor)) ?? []
        let removed = caches.reduce(into: 0) { count, cache in
            guard cache.periodStart <= date && date < cache.periodEnd else { return }
            context.delete(cache)
            count += 1
        }
        if removed > 0 {
            try? context.save()
            Self.logger.notice("StatsDetailRepository aggregate cache invalidated count=\(removed)")
        }
    }

    func invalidateAllAggregateCaches() {
        let descriptor = FetchDescriptor<StatsAggregateCache>()
        let caches = (try? context.fetch(descriptor)) ?? []
        for cache in caches {
            context.delete(cache)
        }
        if !caches.isEmpty {
            try? context.save()
            Self.logger.notice("StatsDetailRepository aggregate cache invalidated count=\(caches.count)")
        }
    }

    func updateSessionMarkerColor(sessionID: UUID, colorKey: String?) throws {
        let descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.id == sessionID }
        )
        guard let session = try context.fetch(descriptor).first else { return }
        session.markerColorKey = colorKey
        try context.save()
    }

    func updateTaskLink(sessionID: UUID, memoID: UUID?) throws {
        let memo: Memo?
        if let memoID {
            var memoDescriptor = FetchDescriptor<Memo>(
                predicate: #Predicate { $0.id == memoID }
            )
            memoDescriptor.fetchLimit = 1
            memo = try context.fetch(memoDescriptor).first
        } else {
            memo = nil
        }
        try FocusSession.updateTaskLink(
            sessionID: sessionID,
            memo: memo,
            modelContext: context
        )
    }

    func updatePomodoroReflection(
        focusSessionID: UUID,
        focusExperience: PomodoroFocusExperience,
        progressResult: PomodoroProgressResult,
        incompleteReason: PomodoroIncompleteReason?
    ) throws {
        let descriptor = FetchDescriptor<PomodoroReflection>(
            predicate: #Predicate { $0.focusSessionID == focusSessionID }
        )
        guard let reflection = try context.fetch(descriptor).first else { return }
        let previousProgressResult = reflection.progressResult

        let sessionDescriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.id == focusSessionID }
        )
        let session = try context.fetch(sessionDescriptor).first

        let existingCompletion = try PomodoroTaskCompletionRecorder.completion(
            focusSessionID: focusSessionID,
            modelContext: context
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
                    modelContext: context
                )
                let recordedCompletion = try PomodoroTaskCompletionRecorder.completion(
                    focusSessionID: focusSessionID,
                    modelContext: context
                )
                didCreateCompletion = existingCompletion == nil && recordedCompletion != nil
            } else if existingCompletion != nil,
                      progressResult != .completedAsPlanned {
                affectedMemo = try PomodoroTaskCompletionRecorder.removeCompletion(
                    focusSessionID: focusSessionID,
                    modelContext: context
                )
            } else {
                affectedMemo = nil
            }

            try context.save()
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
                    modelContext: context
                )
            }
        } catch {
            context.rollback()
            throw error
        }
    }

    func deletePomodoroReflection(focusSessionID: UUID) throws {
        let descriptor = FetchDescriptor<PomodoroReflection>(
            predicate: #Predicate { $0.focusSessionID == focusSessionID }
        )
        guard let reflection = try context.fetch(descriptor).first else { return }

        do {
            let affectedMemo = try PomodoroTaskCompletionRecorder.removeCompletion(
                focusSessionID: focusSessionID,
                modelContext: context
            )
            context.delete(reflection)
            try context.save()
            NotificationCenter.default.post(name: .pomodoroReflectionDidChange, object: nil)
            if let affectedMemo {
                PomodoroTaskCompletionRecorder.applyPostSaveEffects(
                    to: affectedMemo,
                    modelContext: context
                )
            }
        } catch {
            context.rollback()
            throw error
        }
    }

    func hasLinkedMemo(id: UUID) -> Bool {
        PomodoroTaskCompletionRecorder.hasLinkedMemo(id: id, modelContext: context)
    }

    // MARK: - Private Helper Fetchers

    private func attentionSummaryLoadStart(for mode: StatsViewMode, start: Date) -> Date {
        let calendar = Calendar.current
        switch mode {
        case .daily:
            return start
        case .weekly:
            return calendar.date(byAdding: .day, value: -7, to: start) ?? start
        case .monthly:
            return calendar.date(byAdding: .month, value: -1, to: start) ?? start
        }
    }

    private func loadTimerSessions(start: Date, end: Date) -> [FocusSession] {
        let calendar = Calendar.current
        let bufferStart = calendar.date(byAdding: .hour, value: -4, to: start) ?? start
        let descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.startedAt >= bufferStart && $0.startedAt < end },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        let sessions = ((try? context.fetch(descriptor)) ?? []).filter {
            guard let focusEnd = PomodoroComparisonPeriodBuilder.focusEnd(for: $0) else { return false }
            return $0.startedAt < end && focusEnd > start
        }
        return sessions
    }

    private func loadPomodoroReflections(
        for sessions: [FocusSession]
    ) -> [PomodoroReflection] {
        guard !sessions.isEmpty else { return [] }
        let sessionIDs = sessions.map(\.id)
        let descriptor = FetchDescriptor<PomodoroReflection>(
            predicate: #Predicate { sessionIDs.contains($0.focusSessionID) },
            sortBy: [SortDescriptor(\.answeredAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func loadPomodoroTaskCompletions(
        for sessions: [FocusSession]
    ) -> [PomodoroTaskCompletion] {
        guard !sessions.isEmpty else { return [] }
        let sessionIDs = sessions.map(\.id)
        let descriptor = FetchDescriptor<PomodoroTaskCompletion>(
            predicate: #Predicate { sessionIDs.contains($0.focusSessionID) },
            sortBy: [SortDescriptor(\.completedAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func loadBreakTransitionIntents(start: Date, end: Date) -> [BreakTransitionIntent] {
        let descriptor = FetchDescriptor<BreakTransitionIntent>(
            predicate: #Predicate { $0.breakEndedAt >= start && $0.breakEndedAt < end },
            sortBy: [SortDescriptor(\.breakEndedAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func loadSegments(
        for mode: StatsViewMode,
        start: Date,
        end: Date,
        records: [AppUsageRecord],
        timerSessions: [FocusSession],
        aggregateSnapshot: StatsAggregateSnapshot?
    ) -> (daily: [AppUsageSegment], week: [AppUsageSegment], period: [AppUsageSegment]) {
        switch mode {
        case .daily:
            let dayDescriptor = FetchDescriptor<AppUsageSegment>(
                predicate: #Predicate { $0.startTime < end && $0.endTime > start },
                sortBy: [SortDescriptor(\.startTime)]
            )
            let segments = (try? context.fetch(dayDescriptor)) ?? []
            return (segments, [], segments)

        case .weekly:
            if aggregateSnapshot != nil {
                return ([], [], [])
            }
            let weekDescriptor = FetchDescriptor<AppUsageSegment>(
                predicate: #Predicate { $0.startTime < end && $0.endTime > start },
                sortBy: [SortDescriptor(\.startTime)]
            )
            let segments = (try? context.fetch(weekDescriptor)) ?? []
            return ([], segments, segments)

        case .monthly:
            if aggregateSnapshot != nil {
                return ([], [], [])
            }
            if !records.isEmpty {
                return ([], [], [])
            }
            let monthDescriptor = FetchDescriptor<AppUsageSegment>(
                predicate: #Predicate { $0.startTime < end && $0.endTime > start },
                sortBy: [SortDescriptor(\.startTime)]
            )
            let segments = (try? context.fetch(monthDescriptor)) ?? []
            return ([], [], segments)
        }
    }

    private func loadPomodoroSegments(
        for sessions: [FocusSession],
        includedSessionIDs: Set<UUID>,
        availablePeriodSegments: [AppUsageSegment],
        periodSegmentsCoverFullRange: Bool,
        periodStart: Date,
        periodEnd: Date
    ) -> [AppUsageSegment] {
        let completedRanges = sessions.compactMap { session -> (Date, Date)? in
            guard includedSessionIDs.contains(session.id),
                  session.startedAt >= periodStart,
                  session.startedAt < periodEnd,
                  PomodoroComparisonPeriodBuilder.isCompleted(session),
                  let end = PomodoroComparisonPeriodBuilder.focusEnd(for: session) else {
                return nil
            }
            guard end > session.startedAt else { return nil }
            return (session.startedAt, end)
        }
        var segmentsByID = Dictionary(
            uniqueKeysWithValues: availablePeriodSegments.map { ($0.id, $0) }
        )
        let missingRanges = completedRanges.compactMap { rangeStart, rangeEnd in
            guard periodSegmentsCoverFullRange else { return (rangeStart, rangeEnd) }
            guard rangeEnd > periodEnd else { return nil }
            return (max(rangeStart, periodEnd), rangeEnd)
        }
        for (rangeStart, rangeEnd) in mergedPomodoroSegmentRanges(missingRanges) {
            let descriptor = FetchDescriptor<AppUsageSegment>(
                predicate: #Predicate {
                    $0.startTime < rangeEnd && $0.endTime > rangeStart
                },
                sortBy: [SortDescriptor(\.startTime)]
            )
            for segment in (try? context.fetch(descriptor)) ?? [] {
                segmentsByID[segment.id] = segment
            }
        }
        return segmentsByID.values.sorted { $0.startTime < $1.startTime }
    }

    private func mergedPomodoroSegmentRanges(
        _ ranges: [(start: Date, end: Date)]
    ) -> [(start: Date, end: Date)] {
        let maximumGap: TimeInterval = 10 * 60
        let sorted = ranges.sorted { $0.start < $1.start }
        guard var current = sorted.first else { return [] }
        var result: [(start: Date, end: Date)] = []

        for range in sorted.dropFirst() {
            if range.start.timeIntervalSince(current.end) <= maximumGap {
                current.end = max(current.end, range.end)
            } else {
                result.append(current)
                current = range
            }
        }
        result.append(current)
        return result
    }

    private func periodSegmentsCoverFullRange(
        mode: StatsViewMode,
        records: [AppUsageRecord],
        aggregateSnapshot: StatsAggregateSnapshot?
    ) -> Bool {
        switch mode {
        case .daily:
            return true
        case .weekly:
            return aggregateSnapshot == nil
        case .monthly:
            return aggregateSnapshot == nil && records.isEmpty
        }
    }

    private func loadAggregateSnapshot(
        for mode: StatsViewMode,
        start: Date,
        end: Date,
        records: [AppUsageRecord],
        timerSessions: [FocusSession]
    ) -> StatsAggregateSnapshot? {
        guard let scope = StatsAggregateScope.value(for: mode) else { return nil }

        let fingerprint = StatsAggregateBuilder.fingerprint(records: records, sessions: timerSessions)
        let scopedDescriptor = FetchDescriptor<StatsAggregateCache>(
            predicate: #Predicate { $0.scope == scope },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let scopedCaches = (try? context.fetch(scopedDescriptor)) ?? []
        let caches = scopedCaches.filter {
            abs($0.periodStart.timeIntervalSince(start)) < 1 &&
            abs($0.periodEnd.timeIntervalSince(end)) < 1
        }

        if let cache = caches.first(where: { $0.sourceFingerprint == fingerprint }),
           let snapshot = StatsAggregateCacheCodec.decode(cache.payload) {
            let staleCaches = caches.filter { $0.id != cache.id }
            for stale in staleCaches {
                context.delete(stale)
            }
            if !staleCaches.isEmpty {
                try? context.save()
            }
            return snapshot
        }

        if let previousCache = caches.first,
           let previousSnapshot = StatsAggregateCacheCodec.decode(previousCache.payload) {
            let recordSnapshot = StatsAggregateBuilder.build(
                mode: mode,
                start: start,
                end: end,
                records: records,
                segments: [],
                timerSessions: timerSessions
            )
            let refreshedSnapshot = StatsAggregateSnapshot(
                dailyCategories: recordSnapshot.dailyCategories,
                dailyFocusLevels: previousSnapshot.dailyFocusLevels
            )
            if let payload = StatsAggregateCacheCodec.encode(refreshedSnapshot) {
                previousCache.sourceFingerprint = fingerprint
                previousCache.payload = payload
                previousCache.updatedAt = Date()

                let staleCaches = caches.filter { $0.id != previousCache.id }
                for stale in staleCaches {
                    context.delete(stale)
                }
                try? context.save()
            }
            return refreshedSnapshot
        }

        let segmentDescriptor = FetchDescriptor<AppUsageSegment>(
            predicate: #Predicate { $0.startTime < end && $0.endTime > start },
            sortBy: [SortDescriptor(\.startTime)]
        )
        let segments = (try? context.fetch(segmentDescriptor)) ?? []

        let snapshot = StatsAggregateBuilder.build(
            mode: mode,
            start: start,
            end: end,
            records: records,
            segments: segments,
            timerSessions: timerSessions
        )

        guard let payload = StatsAggregateCacheCodec.encode(snapshot) else {
            return snapshot
        }

        for cache in caches {
            context.delete(cache)
        }
        context.insert(StatsAggregateCache(
            scope: scope,
            periodStart: start,
            periodEnd: end,
            sourceFingerprint: fingerprint,
            payload: payload
        ))
        try? context.save()
        return snapshot
    }
}
