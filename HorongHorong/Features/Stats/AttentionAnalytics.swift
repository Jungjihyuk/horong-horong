import Foundation
import SwiftData

enum AttentionFlowState: String, Codable, CaseIterable {
    case steady
    case variable
    case returnNeeded
    case noRecord

    var label: String {
        switch self {
        case .steady: return "흐름 유지"
        case .variable: return "흐름 변동"
        case .returnNeeded: return "복귀 필요"
        case .noRecord: return "기록 대기"
        }
    }

    var emoji: String {
        switch self {
        case .steady: return "🌿"
        case .variable: return "〰️"
        case .returnNeeded: return "↩️"
        case .noRecord: return "⚪️"
        }
    }

    static func fromLegacyValue(_ value: String) -> AttentionFlowState {
        switch value {
        case "steady", "focused":
            return .steady
        case "variable", "moderate":
            return .variable
        case "returnNeeded", "scattered":
            return .returnNeeded
        default:
            return .noRecord
        }
    }
}

enum AttentionEventType: String {
    case selectiveDistraction
    case sustainedDrop
    case delayedReturn
    case allowedSwitch
}

struct AttentionEventCandidate: Identifiable {
    let id = UUID()
    let type: AttentionEventType
    let occurredAt: Date
    let sourceApp: String
    let sourceCategory: String
    let targetCategory: String?
    let durationSeconds: Int
    let confidence: Double

    var fingerprint: String {
        let timestamp = Int(occurredAt.timeIntervalSince1970)
        return [
            type.rawValue,
            String(timestamp),
            sourceApp,
            sourceCategory,
            targetCategory ?? "",
        ].joined(separator: "|")
    }

    var reason: String {
        switch type {
        case .selectiveDistraction:
            return "\(sourceApp)(\(sourceCategory))에 \(durationText) 머물렀어요"
        case .sustainedDrop:
            return "목표 시간보다 \(durationText) 일찍 멈췄어요"
        case .delayedReturn:
            return "휴식 후 복귀가 \(durationText) 늦어졌어요"
        case .allowedSwitch:
            return "\(sourceCategory) 전환은 허용된 흐름으로 봤어요"
        }
    }

    private var durationText: String {
        if durationSeconds < 60 {
            return "\(durationSeconds)초"
        }
        let minutes = durationSeconds / 60
        let seconds = durationSeconds % 60
        return seconds == 0 ? "\(minutes)분" : "\(minutes)분 \(seconds)초"
    }
}

struct AttentionEventCorrection {
    let fingerprint: String
    let verdict: AttentionEventVerdict
}

struct AttentionSummary {
    let selectiveScore: Double
    let sustainedScore: Double
    let returnScore: Double
    let overallScore: Double
    let events: [AttentionEventCandidate]

    static let empty = AttentionSummary(
        selectiveScore: 1,
        sustainedScore: 1,
        returnScore: 1,
        overallScore: 1,
        events: []
    )

    var hasSignals: Bool {
        !events.filter { $0.type != .allowedSwitch }.isEmpty
    }

    var flowState: AttentionFlowState {
        guard hasSignals else { return .steady }
        if overallScore >= 0.75 { return .steady }
        if overallScore >= 0.55 { return .variable }
        return .returnNeeded
    }

    var levelLabel: String {
        flowState.label
    }

    var levelEmoji: String {
        flowState.emoji
    }

    var primaryMessage: String {
        guard let event = primaryEvent else {
            return "방해 앱 체류나 복귀 지연 신호는 크게 보이지 않았어요."
        }

        switch event.type {
        case .selectiveDistraction:
            return "집중 중 방해 가능 앱에 머문 구간이 있었어요."
        case .sustainedDrop:
            return "목표 시간보다 일찍 멈춘 집중 세션이 있었어요."
        case .delayedReturn:
            return "휴식 후 원래 작업 흐름으로 돌아오는 데 시간이 걸렸어요."
        case .allowedSwitch:
            return "전환은 있었지만 허용된 작업 흐름으로 봤어요."
        }
    }

    var primaryEvent: AttentionEventCandidate? {
        let rankedTypes: [AttentionEventType] = [.delayedReturn, .selectiveDistraction, .sustainedDrop]
        for type in rankedTypes {
            if let event = events
                .filter({ $0.type == type })
                .max(by: { $0.durationSeconds < $1.durationSeconds }) {
                return event
            }
        }
        return nil
    }
}

enum AttentionAnalytics {
    static func summary(
        for day: Date,
        segments: [AppUsageSegment],
        timerSessions: [FocusSession],
        thresholds: AttentionThresholds = .standard,
        isAllowedSwitch: ((String, String) -> Bool)? = nil,
        isDistractionCategory: ((String) -> Bool)? = nil,
        breakTransitions: [BreakTransitionIntent] = [],
        corrections: [AttentionEventCorrection] = []
    ) -> AttentionSummary {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: day)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else {
            return .empty
        }

        let clipped = clippedSegments(segments, from: dayStart, to: dayEnd)
        let sessions = timerSessions
            .filter { $0.startedAt < dayEnd && ($0.endedAt ?? dayEnd) > dayStart }
            .sorted { $0.startedAt < $1.startedAt }

        var events: [AttentionEventCandidate] = []
        for session in sessions {
            let targetCategory = session.category ?? Constants.defaultFocusCategory
            let focusEnd = focusWindowEnd(for: session, boundedBy: dayEnd)
            guard focusEnd > session.startedAt else { continue }

            events.append(contentsOf: selectiveDistractionEvents(
                in: clipped,
                session: session,
                focusEnd: focusEnd,
                targetCategory: targetCategory,
                thresholds: thresholds,
                isAllowedSwitch: isAllowedSwitch,
                isDistractionCategory: isDistractionCategory
            ))

            if let sustainedEvent = sustainedDropEvent(
                for: session,
                focusEnd: focusEnd,
                targetCategory: targetCategory,
                thresholds: thresholds
            ) {
                events.append(sustainedEvent)
            }

            if let returnEvent = delayedReturnEvent(
                in: clipped,
                session: session,
                targetCategory: targetCategory,
                dayEnd: dayEnd,
                thresholds: thresholds,
                isAllowedSwitch: isAllowedSwitch,
                breakTransitions: breakTransitions
            ) {
                events.append(returnEvent)
            }
        }

        return buildSummary(events: events, corrections: corrections)
    }

    private static func selectiveDistractionEvents(
        in segments: [ClippedSegment],
        session: FocusSession,
        focusEnd: Date,
        targetCategory: String,
        thresholds: AttentionThresholds,
        isAllowedSwitch: ((String, String) -> Bool)?,
        isDistractionCategory: ((String) -> Bool)?
    ) -> [AttentionEventCandidate] {
        segments.compactMap { segment in
            guard segment.end > session.startedAt, segment.start < focusEnd else { return nil }
            let overlapStart = max(segment.start, session.startedAt)
            let overlapEnd = min(segment.end, focusEnd)
            let overlapSeconds = Int(overlapEnd.timeIntervalSince(overlapStart))
            guard overlapSeconds >= Int(thresholds.distractionMinSeconds) else { return nil }
            guard segment.category != targetCategory else { return nil }

            if isAllowed(category: segment.category, with: targetCategory, isAllowedSwitch: isAllowedSwitch) {
                return AttentionEventCandidate(
                    type: .allowedSwitch,
                    occurredAt: overlapStart,
                    sourceApp: segment.appName,
                    sourceCategory: segment.category,
                    targetCategory: targetCategory,
                    durationSeconds: overlapSeconds,
                    confidence: 0.45
                )
            }

            guard isDistraction(category: segment.category, isDistractionCategory: isDistractionCategory) else { return nil }
            return AttentionEventCandidate(
                type: .selectiveDistraction,
                occurredAt: overlapStart,
                sourceApp: segment.appName,
                sourceCategory: segment.category,
                targetCategory: targetCategory,
                durationSeconds: overlapSeconds,
                confidence: 0.75
            )
        }
    }

    private static func sustainedDropEvent(
        for session: FocusSession,
        focusEnd: Date,
        targetCategory: String,
        thresholds: AttentionThresholds
    ) -> AttentionEventCandidate? {
        guard !session.completed, let endedAt = session.endedAt else { return nil }
        let expectedSeconds = TimeInterval(max(0, session.focusMinutes * 60))
        guard expectedSeconds > 0 else { return nil }
        let actualSeconds = max(0, endedAt.timeIntervalSince(session.startedAt))
        guard actualSeconds < expectedSeconds * thresholds.earlyStopRatio else { return nil }
        return AttentionEventCandidate(
            type: .sustainedDrop,
            occurredAt: endedAt,
            sourceApp: Constants.focusSessionAppName,
            sourceCategory: targetCategory,
            targetCategory: targetCategory,
            durationSeconds: Int(expectedSeconds - actualSeconds),
            confidence: 0.80
        )
    }

    private static func delayedReturnEvent(
        in segments: [ClippedSegment],
        session: FocusSession,
        targetCategory: String,
        dayEnd: Date,
        thresholds: AttentionThresholds,
        isAllowedSwitch: ((String, String) -> Bool)?,
        breakTransitions: [BreakTransitionIntent]
    ) -> AttentionEventCandidate? {
        guard session.completed, let endedAt = session.endedAt else { return nil }
        let expectedReturnAt = endedAt.addingTimeInterval(TimeInterval(max(0, session.breakMinutes * 60)))
        guard expectedReturnAt < dayEnd else { return nil }
        guard !hasResolvedBreakTransition(near: expectedReturnAt, in: breakTransitions) else { return nil }

        let laterSegments = segments.filter { $0.end > expectedReturnAt }.sorted { $0.start < $1.start }
        guard laterSegments.contains(where: { $0.category != targetCategory }) else { return nil }

        let firstTarget = laterSegments.first {
            $0.category == targetCategory
                || isAllowed(category: $0.category, with: targetCategory, isAllowedSwitch: isAllowedSwitch)
        }
        guard let returnSegment = firstTarget else {
            let activeUntil = laterSegments.last?.end ?? dayEnd
            let delaySeconds = Int(activeUntil.timeIntervalSince(expectedReturnAt))
            guard delaySeconds >= Int(thresholds.returnDelaySeconds) else { return nil }
            return AttentionEventCandidate(
                type: .delayedReturn,
                occurredAt: expectedReturnAt,
                sourceApp: laterSegments.first?.appName ?? Constants.focusSessionAppName,
                sourceCategory: laterSegments.first?.category ?? targetCategory,
                targetCategory: targetCategory,
                durationSeconds: delaySeconds,
                confidence: 0.70
            )
        }

        let delaySeconds = Int(max(0, returnSegment.start.timeIntervalSince(expectedReturnAt)))
        guard delaySeconds >= Int(thresholds.returnDelaySeconds) else { return nil }
        let firstOffTarget = laterSegments.first { $0.start < returnSegment.start && $0.category != targetCategory }
        return AttentionEventCandidate(
            type: .delayedReturn,
            occurredAt: expectedReturnAt,
            sourceApp: firstOffTarget?.appName ?? returnSegment.appName,
            sourceCategory: firstOffTarget?.category ?? returnSegment.category,
            targetCategory: targetCategory,
            durationSeconds: delaySeconds,
            confidence: 0.72
        )
    }

    private static func hasResolvedBreakTransition(near expectedReturnAt: Date, in transitions: [BreakTransitionIntent]) -> Bool {
        transitions.contains { transition in
            guard transition.decision != .unresolvedBreak else { return false }
            return abs(transition.breakEndedAt.timeIntervalSince(expectedReturnAt)) <= 120
        }
    }

    private static func buildSummary(
        events: [AttentionEventCandidate],
        corrections: [AttentionEventCorrection]
    ) -> AttentionSummary {
        let correctionMap = Dictionary(uniqueKeysWithValues: corrections.map { ($0.fingerprint, $0.verdict) })
        let visibleEvents = events.filter { event in
            switch correctionMap[event.fingerprint] {
            case .notDistraction, .misclassified:
                return false
            case .distraction, .none:
                return true
            }
        }

        let selectiveEvents = visibleEvents.filter { $0.type == .selectiveDistraction }
        let sustainedEvents = visibleEvents.filter { $0.type == .sustainedDrop }
        let returnEvents = visibleEvents.filter { $0.type == .delayedReturn }

        let selectiveMinutes = Double(selectiveEvents.reduce(0) { $0 + $1.durationSeconds }) / 60
        let sustainedMinutes = Double(sustainedEvents.reduce(0) { $0 + $1.durationSeconds }) / 60
        let returnMinutes = Double(returnEvents.reduce(0) { $0 + $1.durationSeconds }) / 60

        let selectiveScore = clampedScore(1 - Double(selectiveEvents.count) * 0.16 - selectiveMinutes * 0.015)
        let sustainedScore = clampedScore(1 - Double(sustainedEvents.count) * 0.25 - sustainedMinutes * 0.01)
        let returnScore = clampedScore(1 - Double(returnEvents.count) * 0.18 - returnMinutes * 0.012)
        let overallScore = clampedScore(selectiveScore * 0.35 + sustainedScore * 0.30 + returnScore * 0.35)

        return AttentionSummary(
            selectiveScore: selectiveScore,
            sustainedScore: sustainedScore,
            returnScore: returnScore,
            overallScore: overallScore,
            events: visibleEvents.sorted { $0.occurredAt < $1.occurredAt }
        )
    }

    private static func clippedSegments(_ segments: [AppUsageSegment], from start: Date, to end: Date) -> [ClippedSegment] {
        segments.compactMap { segment in
            let clippedStart = max(segment.startTime, start)
            let clippedEnd = min(segment.endTime, end)
            guard clippedEnd > clippedStart else { return nil }
            return ClippedSegment(
                appName: segment.appName,
                category: segment.category,
                start: clippedStart,
                end: clippedEnd
            )
        }
        .sorted { $0.start < $1.start }
    }

    private static func focusWindowEnd(for session: FocusSession, boundedBy dayEnd: Date) -> Date {
        let expectedEnd = session.startedAt.addingTimeInterval(TimeInterval(max(0, session.focusMinutes * 60)))
        let recordedEnd = session.endedAt ?? expectedEnd
        return min(min(recordedEnd, expectedEnd), dayEnd)
    }

    private static func isAllowed(
        category: String,
        with targetCategory: String,
        isAllowedSwitch: ((String, String) -> Bool)?
    ) -> Bool {
        if let isAllowedSwitch {
            return isAllowedSwitch(category, targetCategory)
        }
        return CategoryPairStore.shared.contains(category, targetCategory)
    }

    private static func isDistraction(
        category: String,
        isDistractionCategory: ((String) -> Bool)?
    ) -> Bool {
        if let isDistractionCategory {
            return isDistractionCategory(category)
        }
        return AttentionThresholdStore.shared.isDistractionCategory(category)
    }

    private static func clampedScore(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    private struct ClippedSegment {
        let appName: String
        let category: String
        let start: Date
        let end: Date
    }
}

enum AttentionDaySummaryRecorder {
    static func finalizeCompletedDays(
        from start: Date,
        to end: Date,
        modelContext: ModelContext
    ) -> [AttentionDaySummary] {
        let calendar = Calendar.current
        let rangeStart = calendar.startOfDay(for: start)
        let requestedEnd = calendar.startOfDay(for: end)
        let today = calendar.startOfDay(for: Date())
        let completedEnd = min(requestedEnd, today)

        if rangeStart < completedEnd {
            finalizeDays(
                from: rangeStart,
                to: completedEnd,
                modelContext: modelContext,
                calendar: calendar
            )
        }

        return loadSummaries(from: rangeStart, to: end, modelContext: modelContext)
    }

    private static func finalizeDays(
        from start: Date,
        to end: Date,
        modelContext: ModelContext,
        calendar: Calendar
    ) {
        let records = fetchRecords(from: start, to: end, modelContext: modelContext)
        let segments = fetchSegments(from: start, to: end, modelContext: modelContext)
        let sessions = fetchSessions(from: start, to: end, modelContext: modelContext)
        let breakTransitions = fetchBreakTransitions(from: start, to: end, modelContext: modelContext)
        let corrections = fetchCorrections(from: start, to: end, modelContext: modelContext)
        let existingSummaries = loadSummaries(from: start, to: end, modelContext: modelContext).reduce(into: [:]) {
            result, summary in
            result[summary.dayKey] = result[summary.dayKey] ?? summary
        }

        for day in days(from: start, to: end, calendar: calendar) {
            guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) else { continue }
            let dayRecords = records.filter { $0.date >= day && $0.date < dayEnd }
            let daySegments = segments.filter { $0.startTime < dayEnd && $0.endTime > day }
            let daySessions = sessions.filter {
                guard let focusEnd = focusEnd(for: $0) else { return false }
                return $0.startedAt < dayEnd && focusEnd > day
            }
            let dayCorrections = corrections
                .filter { $0.occurredAt >= day && $0.occurredAt < dayEnd }
                .map { AttentionEventCorrection(fingerprint: $0.fingerprint, verdict: $0.verdict) }
            let dayBreakTransitions = breakTransitions.filter {
                $0.breakEndedAt >= day && $0.breakEndedAt < dayEnd
            }

            let hasAnyRecord = !dayRecords.isEmpty || !daySegments.isEmpty || !daySessions.isEmpty
            let key = dayKey(for: day, calendar: calendar)
            guard hasAnyRecord || existingSummaries[key] != nil else { continue }

            let attentionSummary = AttentionAnalytics.summary(
                for: day,
                segments: daySegments.filter { !Constants.hiddenLegacyCategories.contains($0.category) },
                timerSessions: daySessions,
                thresholds: AttentionThresholdStore.shared.thresholds,
                breakTransitions: dayBreakTransitions,
                corrections: dayCorrections
            )
            let timelineSummary = timelineSummary(
                for: day,
                records: dayRecords,
                segments: daySegments,
                timerSessions: daySessions
            )
            let representative = representativeState(
                attentionSummary: attentionSummary,
                timelineSummary: timelineSummary,
                hasAnyRecord: hasAnyRecord
            )
            let counts = eventCounts(from: attentionSummary)
            upsertSummary(
                existing: existingSummaries[key],
                day: day,
                dayKey: key,
                flowState: representative,
                score: score(attentionSummary: attentionSummary, timelineSummary: timelineSummary),
                counts: counts,
                representativeReason: attentionSummary.primaryEvent?.reason,
                modelContext: modelContext
            )
        }

        try? modelContext.save()
    }

    private static func timelineSummary(
        for day: Date,
        records: [AppUsageRecord],
        segments: [AppUsageSegment],
        timerSessions: [FocusSession]
    ) -> DailyFocusSummary {
        let visibleSegments = segments.filter {
            !Constants.hiddenLegacyCategories.contains($0.category)
        }

        if !visibleSegments.isEmpty {
            let buckets = TimelineAnalytics.buckets(
                for: day,
                segments: visibleSegments,
                timerSessions: timerSessions
            )
            return TimelineAnalytics.summary(
                for: day,
                segments: visibleSegments,
                buckets: buckets,
                timerSessions: timerSessions
            )
        }

        let visibleRecords = records.filter {
            !Constants.hiddenLegacyCategories.contains($0.category)
                && !$0.bundleIdentifier.hasPrefix(Constants.focusSessionBundlePrefix)
        }
        let total = visibleRecords.reduce(0) { $0 + $1.durationSeconds }
        return DailyFocusSummary(
            totalSeconds: total,
            switches: 0,
            longestFocusSeconds: visibleRecords.map(\.durationSeconds).max() ?? 0,
            topCategory: visibleRecords.max { $0.durationSeconds < $1.durationSeconds }?.category,
            overallScore: total == 0 ? 0 : 0.35
        )
    }

    private static func representativeState(
        attentionSummary: AttentionSummary,
        timelineSummary: DailyFocusSummary,
        hasAnyRecord: Bool
    ) -> AttentionFlowState {
        guard hasAnyRecord else { return .noRecord }
        if attentionSummary.hasSignals {
            return attentionSummary.flowState
        }
        return timelineSummary.flowState
    }

    private static func score(
        attentionSummary: AttentionSummary,
        timelineSummary: DailyFocusSummary
    ) -> Double {
        attentionSummary.hasSignals ? attentionSummary.overallScore : timelineSummary.overallScore
    }

    private static func eventCounts(
        from summary: AttentionSummary
    ) -> (selective: Int, sustained: Int, delayedReturn: Int) {
        (
            summary.events.filter { $0.type == .selectiveDistraction }.count,
            summary.events.filter { $0.type == .sustainedDrop }.count,
            summary.events.filter { $0.type == .delayedReturn }.count
        )
    }

    private static func upsertSummary(
        existing: AttentionDaySummary?,
        day: Date,
        dayKey: String,
        flowState: AttentionFlowState,
        score: Double,
        counts: (selective: Int, sustained: Int, delayedReturn: Int),
        representativeReason: String?,
        modelContext: ModelContext
    ) {
        if let existing {
            existing.day = day
            existing.dayKey = dayKey
            existing.flowState = flowState
            existing.overallScore = score
            existing.selectiveEventCount = counts.selective
            existing.sustainedEventCount = counts.sustained
            existing.returnEventCount = counts.delayedReturn
            existing.representativeReason = representativeReason
            existing.updatedAt = Date()
        } else {
            modelContext.insert(AttentionDaySummary(
                day: day,
                dayKey: dayKey,
                flowState: flowState,
                overallScore: score,
                selectiveEventCount: counts.selective,
                sustainedEventCount: counts.sustained,
                returnEventCount: counts.delayedReturn,
                representativeReason: representativeReason
            ))
        }
    }

    private static func fetchRecords(
        from start: Date,
        to end: Date,
        modelContext: ModelContext
    ) -> [AppUsageRecord] {
        let descriptor = FetchDescriptor<AppUsageRecord>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
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
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private static func fetchSessions(
        from start: Date,
        to end: Date,
        modelContext: ModelContext
    ) -> [FocusSession] {
        let calendar = Calendar.current
        let bufferStart = calendar.date(byAdding: .hour, value: -4, to: start) ?? start
        let descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.startedAt >= bufferStart && $0.startedAt < end },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private static func fetchCorrections(
        from start: Date,
        to end: Date,
        modelContext: ModelContext
    ) -> [AttentionEvent] {
        let descriptor = FetchDescriptor<AttentionEvent>(
            predicate: #Predicate { $0.occurredAt >= start && $0.occurredAt < end }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private static func fetchBreakTransitions(
        from start: Date,
        to end: Date,
        modelContext: ModelContext
    ) -> [BreakTransitionIntent] {
        let descriptor = FetchDescriptor<BreakTransitionIntent>(
            predicate: #Predicate { $0.breakEndedAt >= start && $0.breakEndedAt < end },
            sortBy: [SortDescriptor(\.breakEndedAt)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private static func loadSummaries(
        from start: Date,
        to end: Date,
        modelContext: ModelContext
    ) -> [AttentionDaySummary] {
        let descriptor = FetchDescriptor<AttentionDaySummary>(
            predicate: #Predicate { $0.day >= start && $0.day < end },
            sortBy: [SortDescriptor(\.day)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private static func days(from start: Date, to end: Date, calendar: Calendar) -> [Date] {
        var result: [Date] = []
        var cursor = start
        while cursor < end {
            result.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    private static func dayKey(for day: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private static func focusEnd(for session: FocusSession) -> Date? {
        guard let endedAt = session.endedAt else { return nil }
        let expectedEnd = session.startedAt.addingTimeInterval(TimeInterval(max(0, session.focusMinutes) * 60))
        return min(endedAt, expectedEnd)
    }
}
