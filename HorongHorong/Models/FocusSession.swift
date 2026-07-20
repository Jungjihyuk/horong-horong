import Foundation
import SwiftData

extension Notification.Name {
    static let pomodoroReflectionDidChange = Notification.Name(
        "app.horonghorong.pomodoroReflectionDidChange"
    )
    static let pomodoroSessionDidChange = Notification.Name(
        "app.horonghorong.pomodoroSessionDidChange"
    )
    static let pomodoroLinkedTaskDidComplete = Notification.Name(
        "app.horonghorong.pomodoroLinkedTaskDidComplete"
    )
}

@Model
final class FocusSession {
    var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var focusMinutes: Int
    var breakMinutes: Int
    var completed: Bool
    // 사용자가 선택한 통계 카테고리 (nil 이면 미지정 — 과거 기록 호환용)
    var category: String?
    // 성취 목표에 연결된 할 일. 관계 대신 UUID와 제목 스냅샷을 저장해 삭제된 Memo도 설명할 수 있게 한다.
    var linkedMemoID: UUID?
    var taskTitleSnapshot: String?

    init(
        focusMinutes: Int,
        breakMinutes: Int,
        category: String? = nil,
        linkedMemoID: UUID? = nil,
        taskTitleSnapshot: String? = nil
    ) {
        self.id = UUID()
        self.startedAt = Date()
        self.focusMinutes = focusMinutes
        self.breakMinutes = breakMinutes
        self.completed = false
        self.category = category
        self.linkedMemoID = linkedMemoID
        self.taskTitleSnapshot = linkedMemoID == nil ? nil : Self.normalizedText(taskTitleSnapshot)
    }

    private static func normalizedText(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum PomodoroFocusExperience: String, CaseIterable, Identifiable {
    case deeplyFocused = "deeply_focused"
    case mostlyFocused = "mostly_focused"
    case frequentlyDistracted = "frequently_distracted"
    case difficultToFocus = "difficult_to_focus"
    case unsure = "unsure"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .deeplyFocused: return "깊게 몰입했어요"
        case .mostlyFocused: return "대체로 집중했어요"
        case .frequentlyDistracted: return "자주 흐트러졌어요"
        case .difficultToFocus: return "집중하기 어려웠어요"
        case .unsure: return "잘 모르겠어요"
        }
    }
}

enum PomodoroProgressResult: String, CaseIterable, Identifiable {
    case completedAsPlanned = "completed_as_planned"
    case meaningfulProgress = "meaningful_progress"
    case littleProgress = "little_progress"
    case goalChanged = "goal_changed"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .completedAsPlanned: return "계획한 만큼 끝냈어요"
        case .meaningfulProgress: return "의미 있게 진행했지만 남았어요"
        case .littleProgress: return "거의 진행하지 못했어요"
        case .goalChanged: return "진행 중 목표가 바뀌었어요"
        }
    }

    var requiresReason: Bool {
        self != .completedAsPlanned
    }

    func label(recordsLinkedTaskCompletion: Bool) -> String {
        if self == .completedAsPlanned, recordsLinkedTaskCompletion {
            return "이 할 일을 모두 끝냈어요"
        }
        return label
    }
}

enum PomodoroIncompleteReason: String, CaseIterable, Identifiable {
    case insufficientTime = "insufficient_time"
    case underestimatedScope = "underestimated_scope"
    case continuedForQuality = "continued_for_quality"
    case blocked = "blocked"
    case switchedTask = "switched_task"
    case distracted = "distracted"
    case externalInterruption = "external_interruption"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .insufficientTime: return "설정한 시간이 짧았어요"
        case .underestimatedScope: return "예상보다 작업이 컸어요"
        case .continuedForQuality: return "원하는 수준까지 더 다듬고 싶었어요"
        case .blocked: return "막힌 부분이 있었어요"
        case .switchedTask: return "다른 작업으로 옮겼어요"
        case .distracted: return "방해 요소에 집중이 흐트러졌어요"
        case .externalInterruption: return "외부 요청이나 일정이 생겼어요"
        }
    }
}

@Model
final class PomodoroReflection {
    var id: UUID
    @Attribute(.unique)
    var focusSessionID: UUID
    var focusExperienceRawValue: String
    var progressResultRawValue: String
    var incompleteReasonRawValue: String?
    var answeredAt: Date
    var schemaVersion: Int

    init(
        focusSessionID: UUID,
        focusExperience: PomodoroFocusExperience,
        progressResult: PomodoroProgressResult,
        incompleteReason: PomodoroIncompleteReason? = nil,
        answeredAt: Date = Date()
    ) {
        self.id = UUID()
        self.focusSessionID = focusSessionID
        self.focusExperienceRawValue = focusExperience.rawValue
        self.progressResultRawValue = progressResult.rawValue
        self.incompleteReasonRawValue = progressResult.requiresReason ? incompleteReason?.rawValue : nil
        self.answeredAt = answeredAt
        self.schemaVersion = 1
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

    func updateAnswers(
        focusExperience: PomodoroFocusExperience,
        progressResult: PomodoroProgressResult,
        incompleteReason: PomodoroIncompleteReason?
    ) {
        focusExperienceRawValue = focusExperience.rawValue
        progressResultRawValue = progressResult.rawValue
        incompleteReasonRawValue = progressResult.requiresReason ? incompleteReason?.rawValue : nil
    }
}

@Model
final class PomodoroTaskCompletion {
    var id: UUID
    @Attribute(.unique)
    var focusSessionID: UUID
    var linkedMemoID: UUID
    var taskTitleSnapshot: String?
    var completedAt: Date
    var didMarkMemoCompleted: Bool
    var memoWasPinnedBeforeCompletion: Bool
    var memoStateChangedAt: Date?
    var schemaVersion: Int

    init(
        focusSessionID: UUID,
        linkedMemoID: UUID,
        taskTitleSnapshot: String?,
        completedAt: Date = Date(),
        didMarkMemoCompleted: Bool,
        memoWasPinnedBeforeCompletion: Bool
    ) {
        self.id = UUID()
        self.focusSessionID = focusSessionID
        self.linkedMemoID = linkedMemoID
        self.taskTitleSnapshot = Self.normalizedText(taskTitleSnapshot)
        self.completedAt = completedAt
        self.didMarkMemoCompleted = didMarkMemoCompleted
        self.memoWasPinnedBeforeCompletion = memoWasPinnedBeforeCompletion
        self.memoStateChangedAt = didMarkMemoCompleted ? completedAt : nil
        self.schemaVersion = 1
    }

    private static func normalizedText(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

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
        if memo.isCompletedValue || memo.isArchivedValue {
            NotificationManager.shared.cancel(identifier: reminderIdentifier)
        } else if let deadline = memo.deadline,
                  let offset = memo.reminderOffsetMinutes {
            let fireDate = deadline.addingTimeInterval(TimeInterval(-offset * 60))
            let reminderBody = memo.content
                .split(whereSeparator: \.isNewline)
                .map(String.init)
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            NotificationManager.shared.scheduleMemoReminder(
                identifier: reminderIdentifier,
                title: "메모 마감 알림",
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

@MainActor
enum PomodoroSessionDeletion {
    @discardableResult
    static func delete(
        _ session: FocusSession,
        modelContext: ModelContext
    ) throws -> Memo? {
        let sessionID = session.id
        let affectedMemo = try PomodoroTaskCompletionRecorder.removeCompletion(
            focusSessionID: sessionID,
            modelContext: modelContext
        )
        let reflectionDescriptor = FetchDescriptor<PomodoroReflection>(
            predicate: #Predicate { $0.focusSessionID == sessionID }
        )
        for reflection in try modelContext.fetch(reflectionDescriptor) {
            modelContext.delete(reflection)
        }
        modelContext.delete(session)
        return affectedMemo
    }

    static func repairOrphanedRecords(modelContext: ModelContext) throws -> [Memo] {
        let existingSessionIDs = Set(
            try modelContext.fetch(FetchDescriptor<FocusSession>()).map(\.id)
        )
        let completions = try modelContext.fetch(FetchDescriptor<PomodoroTaskCompletion>())
        let memosByID = Dictionary(
            uniqueKeysWithValues: try modelContext.fetch(FetchDescriptor<Memo>()).map {
                ($0.id, $0)
            }
        )
        for completion in completions where completion.didMarkMemoCompleted {
            let stateChangedAt = completion.memoStateChangedAt ?? completion.completedAt
            guard let memo = memosByID[completion.linkedMemoID],
                  memo.isCompletedValue,
                  memo.completionStateChangedAt == nil,
                  memo.updatedAt == stateChangedAt else {
                continue
            }
            memo.completionStateChangedAt = stateChangedAt
        }

        let orphanedCompletionSessionIDs = completions
            .map(\.focusSessionID)
            .filter { !existingSessionIDs.contains($0) }

        var affectedMemosByID: [UUID: Memo] = [:]
        for sessionID in orphanedCompletionSessionIDs {
            if let memo = try PomodoroTaskCompletionRecorder.removeCompletion(
                focusSessionID: sessionID,
                modelContext: modelContext
            ) {
                affectedMemosByID[memo.id] = memo
            }
        }

        let orphanedReflections = try modelContext.fetch(FetchDescriptor<PomodoroReflection>())
            .filter { !existingSessionIDs.contains($0.focusSessionID) }
        for reflection in orphanedReflections {
            modelContext.delete(reflection)
        }
        return Array(affectedMemosByID.values)
    }
}
