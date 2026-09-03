import Foundation
import SwiftData

@MainActor
enum PomodoroTaskCompletionRecorder {
    private struct ReminderSyncJob {
        let token: UUID
        let task: Task<Void, Never>
    }

    private static var reminderSyncJobs: [UUID: ReminderSyncJob] = [:]

    static func completion(
        focusSessionID: UUID,
        modelContext: ModelContext
    ) throws -> PomodoroTaskCompletion? {
        let sessionID = focusSessionID
        var descriptor = FetchDescriptor<PomodoroTaskCompletion>(
            predicate: #Predicate { $0.focusSessionID == sessionID }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    static func shouldRecordCompletionOnEdit(
        previousResult: PomodoroProgressResult?,
        newResult: PomodoroProgressResult,
        hasExistingCompletion: Bool
    ) -> Bool {
        guard newResult == .completedAsPlanned else { return false }
        return hasExistingCompletion || previousResult != .completedAsPlanned
    }

    @discardableResult
    static func recordCompletion(
        for session: FocusSession,
        completedAt: Date,
        modelContext: ModelContext
    ) throws -> Memo? {
        guard let linkedMemoID = session.linkedMemoID else { return nil }
        if try completion(focusSessionID: session.id, modelContext: modelContext) != nil {
            return nil
        }

        guard let memo = try memo(id: linkedMemoID, modelContext: modelContext) else {
            return nil
        }
        let didMarkMemoCompleted = !memo.isCompletedValue
        let memoWasPinned = memo.isPinned
        let completion = PomodoroTaskCompletion(
            focusSessionID: session.id,
            linkedMemoID: linkedMemoID,
            taskTitleSnapshot: session.taskTitleSnapshot,
            completedAt: completedAt,
            didMarkMemoCompleted: didMarkMemoCompleted,
            memoWasPinnedBeforeCompletion: memoWasPinned
        )
        modelContext.insert(completion)

        guard didMarkMemoCompleted else { return nil }
        memo.setCompleted(true, at: completedAt)
        memo.isPinned = false
        memo.updatedAt = completedAt
        return memo
    }

    @discardableResult
    static func removeCompletion(
        focusSessionID: UUID,
        removedAt: Date = Date(),
        modelContext: ModelContext
    ) throws -> Memo? {
        guard let completion = try completion(
            focusSessionID: focusSessionID,
            modelContext: modelContext
        ) else {
            return nil
        }

        let linkedMemoID = completion.linkedMemoID
        let completedAt = completion.completedAt
        let didMarkMemoCompleted = completion.didMarkMemoCompleted
        let memoWasPinnedBeforeCompletion = completion.memoWasPinnedBeforeCompletion
        let memoStateChangedAt = completion.memoStateChangedAt ?? completedAt
        let otherCompletions = try modelContext.fetch(FetchDescriptor<PomodoroTaskCompletion>())
            .filter {
                $0.linkedMemoID == linkedMemoID && $0.focusSessionID != focusSessionID
            }
        modelContext.delete(completion)

        guard
            didMarkMemoCompleted,
            let memo = try memo(id: linkedMemoID, modelContext: modelContext),
            memo.isCompletedValue else {
            return nil
        }
        let currentCompletionStateChangedAt = memo.completionStateChangedAt ?? memo.updatedAt
        guard currentCompletionStateChangedAt == memoStateChangedAt else {
            return nil
        }

        let successor = otherCompletions
            .filter {
                !$0.didMarkMemoCompleted && $0.completedAt >= memoStateChangedAt
            }
            .min(by: { $0.completedAt < $1.completedAt })
        if let successor {
            successor.didMarkMemoCompleted = true
            successor.memoWasPinnedBeforeCompletion = memoWasPinnedBeforeCompletion
            successor.memoStateChangedAt = memoStateChangedAt
            return nil
        }

        memo.setCompleted(false, at: removedAt)
        if !memo.isPinned {
            memo.isPinned = memoWasPinnedBeforeCompletion
        }
        memo.updatedAt = removedAt
        return memo
    }

    static func applyPostSaveEffects(to memo: Memo, modelContext: ModelContext) {
        let reminderIdentifier = "memo.deadline.\(memo.id.uuidString)"
        if memo.isCompletedValue || memo.isRecentlyDeleted {
            NotificationManager.shared.cancel(identifier: reminderIdentifier)
        } else if let fireDate = memo.reminderFireDate {
            let reminderBody = memo.content
                .split(whereSeparator: \.isNewline)
                .map(String.init)
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            NotificationManager.shared.scheduleMemoReminder(
                identifier: reminderIdentifier,
                title: memo.reminderNotificationTitle,
                body: reminderBody.isEmpty ? "제목 없음" : reminderBody,
                at: fireDate
            )
        }

        guard memo.isLinkedToRemindersValue else { return }
        enqueueReminderSync(memoID: memo.id, modelContext: modelContext)
    }

    static func hasLinkedMemo(id: UUID, modelContext: ModelContext) -> Bool {
        (try? memo(id: id, modelContext: modelContext)) != nil
    }

    private static func enqueueReminderSync(memoID: UUID, modelContext: ModelContext) {
        let previousTask = reminderSyncJobs[memoID]?.task
        let token = UUID()
        let task = Task { @MainActor in
            await previousTask?.value
            defer {
                if reminderSyncJobs[memoID]?.token == token {
                    reminderSyncJobs[memoID] = nil
                }
            }

            do {
                guard let memo = try memo(id: memoID, modelContext: modelContext),
                      memo.isLinkedToRemindersValue else {
                    return
                }
                memo.reminderIdentifier = try await MemoReminderLinkService.shared.saveReminder(
                    for: memo
                )
                try modelContext.save()
            } catch {
                guard reminderSyncJobs[memoID]?.token == token else { return }
                ToastPanel.shared.show(
                    icon: "⚠️",
                    title: "미리알림 동기화에 실패했어요",
                    subtitle: "할 일 상태는 호롱호롱에 저장됐어요."
                )
            }
        }
        reminderSyncJobs[memoID] = ReminderSyncJob(token: token, task: task)
    }

    private static func memo(id: UUID, modelContext: ModelContext) throws -> Memo? {
        let memoID = id
        var descriptor = FetchDescriptor<Memo>(
            predicate: #Predicate { $0.id == memoID }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
