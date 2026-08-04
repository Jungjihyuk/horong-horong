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

enum FocusSessionEndKind: String {
    case timerCompleted = "timer_completed"
    case recordedEarly = "recorded_early"
}

/// 포모도로가 실제로 멈춰 있던 벽시계 구간.
struct FocusSessionPauseInterval: Codable, Equatable {
    let startedAt: Date
    let endedAt: Date
}

/// 연속된 세션 시간에서 일시정지 구간을 잘라 실제 집중 구간만 만든다.
enum FocusSessionActivityIntervals {
    static func make(
        startedAt: Date,
        endedAt: Date,
        excluding pauses: [FocusSessionPauseInterval],
        maximumActiveSeconds: TimeInterval? = nil
    ) -> [DateInterval] {
        guard endedAt > startedAt else { return [] }

        var intervals: [DateInterval] = []
        var cursor = startedAt
        for pause in pauses.sorted(by: { $0.startedAt < $1.startedAt }) {
            let pauseStart = max(startedAt, pause.startedAt)
            let pauseEnd = min(endedAt, pause.endedAt)
            guard pauseEnd > cursor else { continue }

            if pauseStart > cursor {
                intervals.append(DateInterval(start: cursor, end: min(pauseStart, endedAt)))
            }
            cursor = max(cursor, pauseEnd)
            guard cursor < endedAt else { break }
        }
        if cursor < endedAt {
            intervals.append(DateInterval(start: cursor, end: endedAt))
        }

        guard let maximumActiveSeconds else { return intervals }
        var remaining = max(0, maximumActiveSeconds)
        var limited: [DateInterval] = []
        for interval in intervals where remaining > 0 {
            let duration = min(interval.duration, remaining)
            guard duration > 0 else { continue }
            limited.append(
                DateInterval(
                    start: interval.start,
                    end: interval.start.addingTimeInterval(duration)
                )
            )
            remaining -= duration
        }
        return limited
    }
}

enum FocusSessionTaskLinkUpdateError: LocalizedError, Equatable {
    case pendingChanges
    case sessionNotFound
    case taskCompletionExists

    var errorDescription: String? {
        switch self {
        case .pendingChanges:
            "저장되지 않은 다른 변경사항이 있어 할 일 연결을 수정할 수 없습니다."
        case .sessionNotFound:
            "수정할 포모도로 세션을 찾을 수 없습니다."
        case .taskCompletionExists:
            "할 일 완료 기록이 있는 세션은 연결을 변경할 수 없습니다."
        }
    }
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
    /// 집중(focusing) 동안 키보드·마우스 입력이 있었던 초. 유휴(입력 없음) 시간은 빼고 센다.
    /// nil = 이 기능 도입 이전에 만들어진 기록(입력 데이터 없음).
    var inputActiveSeconds: Int?
    /// 일시정지를 제외하고 카운트다운이 실제 진행된 초.
    /// nil = 이 기능 도입 이전에 만들어진 기록.
    var actualFocusSeconds: Int?
    /// 닫힌 일시정지 구간을 JSON 으로 저장한다. nil 은 이 기능 도입 이전 세션이다.
    var pauseIntervalsData: Data?
    /// 현재 일시정지가 시작된 시각. 재개하거나 세션을 끝내면 닫힌 구간으로 옮긴다.
    var pauseStartedAt: Date?
    /// 타이머 만료와 사용자의 기록 후 종료를 구분한다.
    var endKindRawValue: String?
    /// 몰입 지도에서 이 세션 점에 쓸 사용자 지정 색 키. nil = 카테고리 기본색.
    var markerColorKey: String?
    /// 완료 직후 회고를 나중에 작성하기로 한 시각. 회고가 저장되면 nil로 되돌린다.
    var reflectionDeferredAt: Date?

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
        self.inputActiveSeconds = nil
        self.actualFocusSeconds = nil
        self.pauseIntervalsData = try? JSONEncoder().encode([FocusSessionPauseInterval]())
        self.pauseStartedAt = nil
        self.endKindRawValue = nil
        self.markerColorKey = nil
        self.reflectionDeferredAt = nil
    }

    private static func normalizedText(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    @MainActor
    static func updateTaskLink(
        sessionID: UUID,
        memo: Memo?,
        modelContext: ModelContext
    ) throws {
        guard !modelContext.hasChanges else {
            throw FocusSessionTaskLinkUpdateError.pendingChanges
        }

        let targetID = sessionID
        var descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.id == targetID }
        )
        descriptor.fetchLimit = 1
        guard let session = try modelContext.fetch(descriptor).first else {
            throw FocusSessionTaskLinkUpdateError.sessionNotFound
        }
        guard try PomodoroTaskCompletionRecorder.completion(
            focusSessionID: sessionID,
            modelContext: modelContext
        ) == nil else {
            throw FocusSessionTaskLinkUpdateError.taskCompletionExists
        }

        session.linkedMemoID = memo?.id
        session.taskTitleSnapshot = memo.map { taskTitle(from: $0.content) }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private static func taskTitle(from content: String) -> String {
        let title = content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? content.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "제목 없는 할 일" : title
    }
}

extension FocusSession {
    /// nil 과 빈 배열을 구분해 과거 세션에는 기존 단일 구간 계산을 유지한다.
    var hasPauseIntervalTracking: Bool {
        pauseIntervalsData != nil
    }

    var pauseIntervals: [FocusSessionPauseInterval] {
        guard let pauseIntervalsData else { return [] }
        return (try? JSONDecoder().decode(
            [FocusSessionPauseInterval].self,
            from: pauseIntervalsData
        )) ?? []
    }

    func recordPauseStarted(at date: Date = Date()) {
        guard pauseStartedAt == nil else { return }
        pauseStartedAt = max(startedAt, date)
    }

    func recordPauseEnded(at date: Date = Date()) {
        guard let pauseStartedAt else { return }
        let pauseEnd = max(pauseStartedAt, date)
        var intervals = pauseIntervals
        if pauseEnd > pauseStartedAt {
            intervals.append(
                FocusSessionPauseInterval(startedAt: pauseStartedAt, endedAt: pauseEnd)
            )
            pauseIntervalsData = try? JSONEncoder().encode(intervals)
        }
        self.pauseStartedAt = nil
    }

    /// 사용자가 시작·종료 시각을 직접 고친 세션은 편집된 범위 전체를 하나의 집중 구간으로 본다.
    func resetPauseIntervalsForContinuousSession() {
        pauseIntervalsData = try? JSONEncoder().encode([FocusSessionPauseInterval]())
        pauseStartedAt = nil
    }

    var endKind: FocusSessionEndKind? {
        get { endKindRawValue.flatMap(FocusSessionEndKind.init(rawValue:)) }
        set { endKindRawValue = newValue?.rawValue }
    }

    var recordedFocusSeconds: Int {
        let plannedSeconds = max(0, focusMinutes * 60)
        guard plannedSeconds > 0 else { return 0 }
        if let actualFocusSeconds {
            return min(plannedSeconds, max(0, actualFocusSeconds))
        }
        guard let endedAt else { return 0 }
        return min(
            plannedSeconds,
            max(0, Int(endedAt.timeIntervalSince(startedAt)))
        )
    }

    @MainActor
    @discardableResult
    static func resetMarkerColors(
        for category: String,
        in modelContext: ModelContext
    ) throws -> Int {
        guard !modelContext.hasChanges else {
            throw CategoryBehaviorConditionSetValidationError.pendingChanges
        }

        do {
            let sessions = try modelContext.fetch(FetchDescriptor<FocusSession>())
            let customizedSessions = sessions.filter {
                $0.category == category && $0.markerColorKey != nil
            }
            for session in customizedSessions {
                session.markerColorKey = nil
            }
            if !customizedSessions.isEmpty {
                try modelContext.save()
            }
            return customizedSessions.count
        } catch {
            modelContext.rollback()
            throw error
        }
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
final class CategoryBehaviorConditionSet {
    var id: UUID
    @Attribute(.unique)
    var category: String
    var maximumAppSwitchesPerAttributedTenMinutes: Double?
    var maximumCategorySwitchesPerAttributedTenMinutes: Double?
    var minimumLongestContinuousAppCategoryRatio: Double?
    var createdAt: Date
    var updatedAt: Date
    var schemaVersion: Int

    init(
        category: String,
        maximumAppSwitchesPerAttributedTenMinutes: Double? = nil,
        maximumCategorySwitchesPerAttributedTenMinutes: Double? = nil,
        minimumLongestContinuousAppCategoryRatio: Double? = nil,
        createdAt: Date = Date()
    ) {
        self.id = UUID()
        self.category = category.trimmingCharacters(in: .whitespacesAndNewlines)
        self.maximumAppSwitchesPerAttributedTenMinutes =
            maximumAppSwitchesPerAttributedTenMinutes
        self.maximumCategorySwitchesPerAttributedTenMinutes =
            maximumCategorySwitchesPerAttributedTenMinutes
        self.minimumLongestContinuousAppCategoryRatio =
            minimumLongestContinuousAppCategoryRatio
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.schemaVersion = 1
    }

    var conditionCount: Int {
        [
            maximumAppSwitchesPerAttributedTenMinutes,
            maximumCategorySwitchesPerAttributedTenMinutes,
            minimumLongestContinuousAppCategoryRatio,
        ].compactMap { $0 }.count
    }

    func update(
        maximumAppSwitchesPerAttributedTenMinutes: Double?,
        maximumCategorySwitchesPerAttributedTenMinutes: Double?,
        minimumLongestContinuousAppCategoryRatio: Double?,
        updatedAt: Date = Date()
    ) {
        self.maximumAppSwitchesPerAttributedTenMinutes =
            maximumAppSwitchesPerAttributedTenMinutes
        self.maximumCategorySwitchesPerAttributedTenMinutes =
            maximumCategorySwitchesPerAttributedTenMinutes
        self.minimumLongestContinuousAppCategoryRatio =
            minimumLongestContinuousAppCategoryRatio
        self.updatedAt = updatedAt
    }
}

enum CategoryBehaviorConditionSetValidationError: LocalizedError {
    case emptyCategory
    case invalidSwitchLimit
    case invalidContinuousRatio
    case pendingChanges

    var errorDescription: String? {
        switch self {
        case .emptyCategory:
            return "카테고리를 확인해 주세요."
        case .invalidSwitchLimit:
            return "전환 기준은 0 이상의 숫자로 입력해 주세요."
        case .invalidContinuousRatio:
            return "이어진 비율은 0%에서 100% 사이로 입력해 주세요."
        case .pendingChanges:
            return "다른 변경 내용을 저장한 뒤 다시 시도해 주세요."
        }
    }
}

@MainActor
enum CategoryBehaviorConditionSetStore {
    @discardableResult
    static func upsert(
        category: String,
        maximumAppSwitchesPerAttributedTenMinutes: Double?,
        maximumCategorySwitchesPerAttributedTenMinutes: Double?,
        minimumLongestContinuousAppCategoryRatio: Double?,
        modelContext: ModelContext
    ) throws -> CategoryBehaviorConditionSet? {
        let normalizedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCategory.isEmpty else {
            throw CategoryBehaviorConditionSetValidationError.emptyCategory
        }
        try validateSwitchLimit(maximumAppSwitchesPerAttributedTenMinutes)
        try validateSwitchLimit(maximumCategorySwitchesPerAttributedTenMinutes)
        if let ratio = minimumLongestContinuousAppCategoryRatio,
           !ratio.isFinite || !(0...1).contains(ratio) {
            throw CategoryBehaviorConditionSetValidationError.invalidContinuousRatio
        }
        let normalizedMaximumAppSwitches = normalizedSwitchLimit(
            maximumAppSwitchesPerAttributedTenMinutes
        )
        let normalizedMaximumCategorySwitches = normalizedSwitchLimit(
            maximumCategorySwitchesPerAttributedTenMinutes
        )
        let normalizedMinimumContinuousRatio = normalizedContinuousRatio(
            minimumLongestContinuousAppCategoryRatio
        )
        guard !modelContext.hasChanges else {
            throw CategoryBehaviorConditionSetValidationError.pendingChanges
        }

        do {
            let existing = try conditionSets(
                category: normalizedCategory,
                modelContext: modelContext
            )
            guard normalizedMaximumAppSwitches != nil
                    || normalizedMaximumCategorySwitches != nil
                    || normalizedMinimumContinuousRatio != nil else {
                for conditionSet in existing {
                    modelContext.delete(conditionSet)
                }
                try modelContext.save()
                return nil
            }

            let conditionSet: CategoryBehaviorConditionSet
            if let first = existing.first {
                conditionSet = first
                for duplicate in existing.dropFirst() {
                    modelContext.delete(duplicate)
                }
                conditionSet.update(
                    maximumAppSwitchesPerAttributedTenMinutes:
                        normalizedMaximumAppSwitches,
                    maximumCategorySwitchesPerAttributedTenMinutes:
                        normalizedMaximumCategorySwitches,
                    minimumLongestContinuousAppCategoryRatio:
                        normalizedMinimumContinuousRatio
                )
            } else {
                conditionSet = CategoryBehaviorConditionSet(
                    category: normalizedCategory,
                    maximumAppSwitchesPerAttributedTenMinutes:
                        normalizedMaximumAppSwitches,
                    maximumCategorySwitchesPerAttributedTenMinutes:
                        normalizedMaximumCategorySwitches,
                    minimumLongestContinuousAppCategoryRatio:
                        normalizedMinimumContinuousRatio
                )
                modelContext.insert(conditionSet)
            }
            try modelContext.save()
            return conditionSet
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    static func delete(
        category: String,
        modelContext: ModelContext
    ) throws {
        guard !modelContext.hasChanges else {
            throw CategoryBehaviorConditionSetValidationError.pendingChanges
        }
        do {
            try prepareCategoryDeletion(category: category, modelContext: modelContext)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    static func prepareCategoryRename(
        from oldCategory: String,
        to newCategory: String,
        modelContext: ModelContext
    ) throws {
        let oldName = oldCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        let newName = newCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !oldName.isEmpty, !newName.isEmpty, oldName != newName else { return }

        let source = try conditionSets(category: oldName, modelContext: modelContext)
        guard let firstSource = source.first else { return }
        for duplicate in source.dropFirst() {
            modelContext.delete(duplicate)
        }
        for target in try conditionSets(category: newName, modelContext: modelContext) {
            modelContext.delete(target)
        }
        firstSource.category = newName
        firstSource.updatedAt = Date()
    }

    static func prepareCategoryDeletion(
        category: String,
        modelContext: ModelContext
    ) throws {
        let normalizedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCategory.isEmpty else { return }
        for conditionSet in try conditionSets(
            category: normalizedCategory,
            modelContext: modelContext
        ) {
            modelContext.delete(conditionSet)
        }
    }

    private static func validateSwitchLimit(_ value: Double?) throws {
        if let value, !value.isFinite || value < 0 {
            throw CategoryBehaviorConditionSetValidationError.invalidSwitchLimit
        }
    }

    private static func normalizedSwitchLimit(_ value: Double?) -> Double? {
        value.map { ($0 * 10).rounded() / 10 }
    }

    private static func normalizedContinuousRatio(_ value: Double?) -> Double? {
        value.map { ($0 * 100).rounded() / 100 }
    }

    private static func conditionSets(
        category: String,
        modelContext: ModelContext
    ) throws -> [CategoryBehaviorConditionSet] {
        let targetCategory = category
        return try modelContext.fetch(
            FetchDescriptor<CategoryBehaviorConditionSet>(
                predicate: #Predicate { $0.category == targetCategory },
                sortBy: [SortDescriptor(\.createdAt)]
            )
        )
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
