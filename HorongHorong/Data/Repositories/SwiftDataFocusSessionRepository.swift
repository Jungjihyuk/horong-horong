import Foundation
import SwiftData

/// `FocusSessionRepository` 의 SwiftData 구현.
@MainActor
final class SwiftDataFocusSessionRepository: FocusSessionRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func startFocus(
        focusMinutes: Int,
        breakMinutes: Int,
        category: String?,
        linkedMemoID: UUID?,
        taskTitleSnapshot: String?
    ) -> UUID {
        let session = FocusSession(
            focusMinutes: focusMinutes,
            breakMinutes: breakMinutes,
            category: category,
            linkedMemoID: linkedMemoID,
            taskTitleSnapshot: taskTitleSnapshot
        )
        context.insert(session)
        try? context.save()
        return session.id
    }

    func recordPauseStarted(id: UUID, at date: Date) {
        guard let session = find(id) else { return }
        session.recordPauseStarted(at: date)
        try? context.save()
    }

    func recordPauseEnded(id: UUID, at date: Date) {
        guard let session = find(id) else { return }
        session.recordPauseEnded(at: date)
        try? context.save()
    }

    @discardableResult
    func finishFocus(
        id: UUID,
        endedAt: Date,
        actualSeconds: Int,
        inputActiveSeconds: Int,
        endKind: FocusSessionEndKind
    ) -> FinishedFocusSession? {
        guard let session = find(id) else { return nil }

        // 멈춘 채로 끝냈을 수 있다. 열려 있는 멈춤 구간을 닫아야 집중 시간이 맞는다.
        session.recordPauseEnded(at: endedAt)
        session.endedAt = endedAt
        session.completed = true
        session.actualFocusSeconds = actualSeconds
        session.endKind = endKind
        session.inputActiveSeconds = inputActiveSeconds
        try? context.save()

        applyUsageDelta(for: session)

        return FinishedFocusSession(
            id: session.id,
            linkedMemoID: session.linkedMemoID,
            taskTitleSnapshot: session.taskTitleSnapshot,
            isTaskStillOpen: isTaskStillOpen(memoID: session.linkedMemoID)
        )
    }

    func discardFocus(id: UUID) {
        guard let session = find(id) else { return }
        context.delete(session)
        try? context.save()
    }

    func abandonFocus(id: UUID, endedAt: Date) {
        guard let session = find(id), !session.completed else { return }
        session.endedAt = endedAt
        session.completed = false
        try? context.save()
    }

    // MARK: - 조회

    func hasFocusSession(startingAfter date: Date) -> Bool {
        let descriptor = FetchDescriptor<FocusSession>(predicate: #Predicate { $0.startedAt > date })
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    func isTaskStillOpen(memoID: UUID?) -> Bool {
        // 연결된 할 일이 없으면 «이어서 하기» 를 막을 이유가 없다.
        guard let memoID else { return true }
        var descriptor = FetchDescriptor<SecondBrainRecord>(predicate: #Predicate { $0.id == memoID })
        descriptor.fetchLimit = 1
        guard let record = try? context.fetch(descriptor).first else { return false }
        return !record.isCompletedValue && !record.isRecentlyDeleted
    }

    func hasProductiveActivity(since date: Date, minimumSeconds: Int) -> Bool {
        let descriptor = FetchDescriptor<AppUsageSegment>(predicate: #Predicate { $0.endTime > date })
        let segments = (try? context.fetch(descriptor)) ?? []
        let productiveSeconds = segments.reduce(0) { total, segment in
            guard Constants.postBreakProductiveCategories.contains(segment.category) else { return total }
            // 구간이 기준 시각에 걸쳐 있으면 그 뒤쪽만 센다.
            let start = max(segment.startTime, date)
            guard segment.endTime > start else { return total }
            return total + Int(segment.endTime.timeIntervalSince(start))
        }
        return productiveSeconds >= minimumSeconds
    }

    func recordBreakTransition(
        breakEndedAt: Date,
        decision: BreakTransitionDecisionKind,
        previousCategory: String,
        nextCategory: String?
    ) {
        context.insert(BreakTransitionIntent(
            breakEndedAt: breakEndedAt,
            decision: decision,
            previousCategory: previousCategory,
            nextCategory: nextCategory
        ))
        try? context.save()
    }

    // MARK: - 내부

    /// 끝난 집중을 그날의 앱 사용 기록에 더한다. 집중 시간도 «쓴 시간» 이라 통계에 들어간다.
    private func applyUsageDelta(for session: FocusSession) {
        let category = session.category ?? Constants.defaultFocusCategory
        let seconds = session.recordedFocusSeconds
        guard seconds > 0 else { return }

        let today = Calendar.current.startOfDay(for: session.endedAt ?? Date())
        try? AppUsageRecordStore.applyDelta(
            bundleIdentifier: Constants.focusSessionBundleId(for: category),
            appName: Constants.focusSessionAppName,
            category: category,
            date: today,
            deltaSeconds: seconds,
            modelContext: context
        )
        try? context.save()
    }

    private func find(_ id: UUID) -> FocusSession? {
        var descriptor = FetchDescriptor<FocusSession>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
