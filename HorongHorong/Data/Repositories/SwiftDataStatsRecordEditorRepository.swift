import Foundation
import SwiftData

@MainActor
final class SwiftDataStatsRecordEditorRepository: StatsRecordEditorRepository {
    private let context: ModelContext
    private let calendar: Calendar

    init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    func snapshot(on date: Date) throws -> StatsRecordEditorSnapshot {
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return StatsRecordEditorSnapshot(segments: [], focusSessions: [])
        }
        let segments = try context.fetch(FetchDescriptor<AppUsageSegment>(
            predicate: #Predicate { $0.startTime < dayEnd && $0.endTime > dayStart },
            sortBy: [SortDescriptor(\.startTime)]
        ))
        let bufferStart = calendar.date(byAdding: .hour, value: -4, to: dayStart) ?? dayStart
        let sessions = try context.fetch(FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.startedAt >= bufferStart && $0.startedAt < dayEnd },
            sortBy: [SortDescriptor(\.startedAt)]
        )).compactMap { session -> StatsEditableFocusSession? in
            guard isCompletedPomodoro(session), let end = focusEnd(for: session),
                  session.startedAt < dayEnd, end > dayStart else {
                return nil
            }
            return focusValue(session, end: end)
        }
        return StatsRecordEditorSnapshot(
            segments: segments.map(segmentValue),
            focusSessions: sessions
        )
    }

    func addSegment(_ draft: StatsSegmentDraft) throws {
        do {
            let bundleIdentifier = manualBundleIdentifier(for: draft.appName)
            let segment = AppUsageSegment(
                appName: draft.appName,
                bundleIdentifier: bundleIdentifier,
                category: draft.category,
                startTime: draft.start,
                endTime: draft.end,
                isManual: true
            )
            context.insert(segment)
            try syncRecord(
                bundleIdentifier: bundleIdentifier,
                appName: draft.appName,
                category: draft.category,
                date: draft.start,
                deltaSeconds: segment.durationSeconds
            )
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func updateSegment(id: UUID, draft: StatsSegmentDraft) throws {
        do {
            let segment = try segment(id: id)
            let oldBundleIdentifier = segment.bundleIdentifier
            let oldAppName = segment.appName
            let oldCategory = segment.category
            let oldDate = segment.startTime
            let oldDuration = segment.durationSeconds
            let newBundleIdentifier = segment.isManual
                ? manualBundleIdentifier(for: draft.appName)
                : oldBundleIdentifier

            segment.appName = draft.appName
            segment.bundleIdentifier = newBundleIdentifier
            segment.category = draft.category
            segment.startTime = draft.start
            segment.endTime = draft.end
            segment.isUserModified = true

            try syncRecord(
                bundleIdentifier: oldBundleIdentifier,
                appName: oldAppName,
                category: oldCategory,
                date: oldDate,
                deltaSeconds: -oldDuration
            )
            try syncRecord(
                bundleIdentifier: newBundleIdentifier,
                appName: draft.appName,
                category: draft.category,
                date: draft.start,
                deltaSeconds: segment.durationSeconds
            )
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func deleteSegment(id: UUID) throws {
        do {
            let segment = try segment(id: id)
            try syncRecord(
                bundleIdentifier: segment.bundleIdentifier,
                appName: segment.appName,
                category: segment.category,
                date: segment.startTime,
                deltaSeconds: -segment.durationSeconds
            )
            context.delete(segment)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func updateFocusSession(id: UUID, draft: StatsFocusSessionDraft) throws {
        do {
            let session = try focusSession(id: id)
            guard focusEnd(for: session) != nil else {
                throw StatsRecordEditorError.missingFocusEnd
            }
            let oldCategory = session.category ?? Constants.defaultFocusCategory
            let oldStart = session.startedAt
            let oldDuration = session.recordedFocusSeconds
            let newDuration = Int(draft.end.timeIntervalSince(draft.start))

            session.category = draft.category
            session.startedAt = draft.start
            session.endedAt = draft.end
            session.focusMinutes = max(1, Int(ceil(draft.end.timeIntervalSince(draft.start) / 60)))
            session.completed = true
            session.actualFocusSeconds = newDuration
            session.resetPauseIntervalsForContinuousSession()

            try syncFocusRecord(category: oldCategory, date: oldStart, deltaSeconds: -oldDuration)
            try syncFocusRecord(category: draft.category, date: draft.start, deltaSeconds: newDuration)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func deleteFocusSession(id: UUID) throws {
        do {
            let session = try focusSession(id: id)
            guard let end = focusEnd(for: session) else {
                throw StatsRecordEditorError.missingFocusEnd
            }
            let start = session.startedAt
            let overlappingSegments = try context.fetch(FetchDescriptor<AppUsageSegment>(
                predicate: #Predicate { $0.startTime < end && $0.endTime > start }
            ))
            for segment in overlappingSegments {
                try removeSegmentOverlap(segment, from: start, to: end)
            }
            try deleteFocusRecord(for: session)
            let affectedMemo = try PomodoroSessionDeletion.delete(session, modelContext: context)
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

    private func segment(id: UUID) throws -> AppUsageSegment {
        let targetID = id
        var descriptor = FetchDescriptor<AppUsageSegment>(
            predicate: #Predicate { $0.id == targetID }
        )
        descriptor.fetchLimit = 1
        guard let segment = try context.fetch(descriptor).first else {
            throw StatsRecordEditorError.recordNotFound
        }
        return segment
    }

    private func focusSession(id: UUID) throws -> FocusSession {
        let targetID = id
        var descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.id == targetID }
        )
        descriptor.fetchLimit = 1
        guard let session = try context.fetch(descriptor).first else {
            throw StatsRecordEditorError.recordNotFound
        }
        return session
    }

    private func removeSegmentOverlap(
        _ segment: AppUsageSegment,
        from start: Date,
        to end: Date
    ) throws {
        let overlapStart = max(segment.startTime, start)
        let overlapEnd = min(segment.endTime, end)
        guard overlapEnd > overlapStart else { return }

        let removedSeconds = Int(overlapEnd.timeIntervalSince(overlapStart))
        let originalStart = segment.startTime
        let originalEnd = segment.endTime
        let bundleIdentifier = segment.bundleIdentifier
        let appName = segment.appName
        let category = segment.category
        let isManual = segment.isManual
        let isUserModified = segment.isUserModified || segment.isManual

        if overlapStart <= originalStart, overlapEnd >= originalEnd {
            context.delete(segment)
        } else if overlapStart <= originalStart {
            segment.startTime = overlapEnd
        } else if overlapEnd >= originalEnd {
            segment.endTime = overlapStart
        } else {
            segment.endTime = overlapStart
            context.insert(AppUsageSegment(
                appName: appName,
                bundleIdentifier: bundleIdentifier,
                category: category,
                startTime: overlapEnd,
                endTime: originalEnd,
                isManual: isManual,
                isUserModified: isUserModified
            ))
        }

        try syncRecord(
            bundleIdentifier: bundleIdentifier,
            appName: appName,
            category: category,
            date: originalStart,
            deltaSeconds: -removedSeconds
        )
    }

    private func deleteFocusRecord(for session: FocusSession) throws {
        let duration = session.recordedFocusSeconds
        guard duration > 0 else { return }
        let category = session.category ?? Constants.defaultFocusCategory
        try syncFocusRecord(category: category, date: session.startedAt, deltaSeconds: -duration)
    }

    private func syncFocusRecord(category: String, date: Date, deltaSeconds: Int) throws {
        try syncRecord(
            bundleIdentifier: Constants.focusSessionBundleId(for: category),
            appName: Constants.focusSessionAppName,
            category: category,
            date: date,
            deltaSeconds: deltaSeconds
        )
    }

    private func syncRecord(
        bundleIdentifier: String,
        appName: String,
        category: String,
        date: Date,
        deltaSeconds: Int
    ) throws {
        try AppUsageRecordStore.applyDelta(
            bundleIdentifier: bundleIdentifier,
            appName: appName,
            category: category,
            date: date,
            deltaSeconds: deltaSeconds,
            modelContext: context
        )
    }

    private func focusValue(_ session: FocusSession, end: Date) -> StatsEditableFocusSession {
        StatsEditableFocusSession(
            id: session.id,
            category: session.category ?? Constants.defaultFocusCategory,
            start: session.startedAt,
            end: end,
            durationSeconds: session.recordedFocusSeconds
        )
    }

    private func segmentValue(_ segment: AppUsageSegment) -> StatsEditableSegment {
        StatsEditableSegment(
            id: segment.id,
            appName: segment.appName,
            category: segment.category,
            start: segment.startTime,
            end: segment.endTime,
            isManual: segment.isManual,
            isUserModified: segment.isUserModified
        )
    }

    private func isCompletedPomodoro(_ session: FocusSession) -> Bool {
        guard let endedAt = session.endedAt else { return false }
        let expectedSeconds = max(0, session.focusMinutes) * 60
        return expectedSeconds > 0
            && (session.completed || endedAt.timeIntervalSince(session.startedAt) >= Double(expectedSeconds))
    }

    private func focusEnd(for session: FocusSession) -> Date? {
        guard let endedAt = session.endedAt else { return nil }
        let expectedEnd = session.startedAt.addingTimeInterval(Double(max(0, session.focusMinutes) * 60))
        return min(endedAt, expectedEnd)
    }

    private func manualBundleIdentifier(for appName: String) -> String {
        "manual.\(appName.lowercased().replacingOccurrences(of: " ", with: "-"))"
    }
}
