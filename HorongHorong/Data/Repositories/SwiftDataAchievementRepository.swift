import Foundation
import SwiftData

/// `AchievementRepository` 의 SwiftData 구현.
///
/// 목표 사이의 부모·자식 관계는 **외래키가 아니라 제목 문자열**로 이어져 있다
/// (`yearGoal`·`monthGoal` 에 부모 제목이 들어간다). 그래서 제목을 고치면 자식들의
/// 참조도 함께 고쳐야 한다 — `syncTitleReferences` 가 그 일을 한다.
/// 이 사정이 화면으로 새지 않도록 여기 가둔다.
@MainActor
final class SwiftDataAchievementRepository: AchievementRepository {
    /// 목표·할일이 바뀌었다. 성취 창과 팝오버 요약이 함께 보므로 `@Query` 자동 갱신을
    /// 이 알림으로 대신한다(`SwiftDataRewardRepository` 와 같은 방식).
    static let didChangeNotification = Notification.Name("AchievementDataDidChange")

    private let context: ModelContext
    private let reminders: MemoReminderLinkService
    private let notifications: NotificationManager

    init(
        context: ModelContext,
        reminders: MemoReminderLinkService = .shared,
        notifications: NotificationManager = .shared
    ) {
        self.context = context
        self.reminders = reminders
        self.notifications = notifications
    }

    // MARK: - 조회

    func goals() -> [AchievementGoalDetail] {
        goalRecords().map(Self.toDetail)
    }

    func memos() -> [AchievementMemoDetail] {
        activeMemoRecords().map(Self.toMemoDetail)
    }

    func linkableMemos() -> [AchievementMemoDetail] {
        activeMemoRecords()
            .filter { !$0.isCompletedValue }
            .map(Self.toMemoDetail)
    }

    // MARK: - 목표 쓰기

    @discardableResult
    func createGoal(
        _ draft: AchievementGoalDraft,
        childGoalIDs: Set<UUID>,
        newChildTitles: [String]
    ) throws -> AchievementGoalDetail {
        // 남의 할일은 못 가져온다. 화면이 이미 잠가 두지만 창이 둘 열려 있으면 뚫린다.
        let linkedMemoIDs = AchievementMemoLinkPolicy.sanitized(
            linkedMemoIDs: draft.linkedMemoIDs,
            cadence: draft.cadence,
            goalID: nil,
            existingGoals: goals()
        )
        let record = AchievementGoalRecord(
            title: draft.title,
            emoji: draft.emoji,
            cadence: draft.cadence,
            rule: draft.rule,
            // 걸러낸 연결 수에 목표치를 맞춘다. 안 맞추면 못 가져온 할일까지 세어
            // 달성할 수 없는 목표가 된다.
            targetCount: draft.linkedMemoIDs.isEmpty
                ? draft.targetCount
                : max(1, draft.targetCount - (draft.linkedMemoIDs.count - linkedMemoIDs.count)),
            targetValueText: draft.targetValueText,
            periodText: draft.periodText,
            dueDate: draft.dueDate,
            rewardText: "",
            colorHex: draft.colorHex,
            roleName: draft.roleName,
            vision: draft.vision,
            yearGoal: draft.yearGoal,
            quarterGoal: nil,
            monthGoal: draft.monthGoal,
            linkedMemoIDs: linkedMemoIDs
        )
        // 추천에서 온 목표면 출처를 심는다. 직접 만든 목표는 nil 로 남아 둘이 갈린다.
        record.sourceRunID = draft.sourceRunID
        record.sourceSuggestionID = draft.sourceSuggestionID
        context.insert(record)

        connectChildGoals(childGoalIDs, to: record)
        // 제목만 적어둔 하위 목표는 여기서 실제 레코드로 만든다.
        for childTitle in newChildTitles {
            addChildGoal(to: record, title: childTitle, emoji: "")
        }
        try saveThrowing()
        return Self.toDetail(record)
    }

    func markCompleted(ids: [UUID], at date: Date) {
        guard !ids.isEmpty else { return }
        var changed = false
        for id in ids {
            guard let record = findGoal(id), record.completedAt == nil else { continue }
            record.completedAt = date
            changed = true
        }
        guard changed else { return }
        save()
    }

    func updateGoal(id: UUID, with edit: AchievementGoalEditDraft) {
        guard let record = findGoal(id) else { return }
        let oldTitle = record.title
        let newTitle = edit.title.trimmingCharacters(in: .whitespacesAndNewlines)

        record.title = newTitle.isEmpty ? record.title : newTitle
        let emoji = edit.emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        record.emoji = emoji.isEmpty ? record.emoji : edit.emoji
        record.rule = edit.rule.trimmingCharacters(in: .whitespacesAndNewlines)
        record.targetCount = max(1, edit.targetCount)
        record.rewardText = edit.rewardText.trimmingCharacters(in: .whitespacesAndNewlines)
        record.dueDate = edit.dueDate
        if let requestedMemoIDs = edit.linkedMemoIDs {
            // 남의 할일은 못 가져온다. 자기가 이미 묶어 둔 것은 그대로 둔다.
            let linkedMemoIDs = AchievementMemoLinkPolicy.sanitized(
                linkedMemoIDs: requestedMemoIDs,
                cadence: record.cadence,
                goalID: record.id,
                existingGoals: goals()
            )
            record.linkedMemoIDs = linkedMemoIDs
            record.targetCount = max(1, linkedMemoIDs.count)
        }
        if let additional = edit.additionalChildGoalIDs, !additional.isEmpty {
            for child in goalRecords() where additional.contains(child.id) {
                if record.cadence == "연간" { child.yearGoal = record.title }
                if record.cadence == "월간" { child.monthGoal = record.title }
                child.updatedAt = Date()
            }
        }
        record.updatedAt = Date()

        syncTitleReferences(oldTitle: oldTitle, newTitle: record.title, cadence: record.cadence)
        connectDescendantGoals(of: record)
        save()
    }

    func deleteGoal(id: UUID) {
        guard let record = findGoal(id) else { return }
        context.delete(record)
        save()
    }

    func detachChild(id: UUID, fromParentID: UUID) {
        guard let child = findGoal(id), let parent = findGoal(fromParentID) else { return }
        switch parent.cadence {
        case "연간": child.yearGoal = nil
        case "월간": child.monthGoal = nil
        default: return
        }
        child.updatedAt = Date()
        save()
    }

    func savePersonaVision(_ draft: AchievementPersonaVisionDraft) throws {
        let personaName = Self.shortText(draft.personaName, limit: 40)
        let visionTitle = Self.shortText(draft.visionTitle, limit: 40)
        let visionText = draft.visionText.trimmingCharacters(in: .whitespacesAndNewlines)

        // 같은 이름의 역할이 이미 있으면 다시 만들지 않는다.
        if !goalRecords().contains(where: { $0.cadence == "역할" && $0.title == personaName }) {
            context.insert(AchievementGoalRecord(
                title: personaName,
                emoji: draft.personaEmoji,
                cadence: "역할",
                rule: "페르소나 방향 유지",
                targetCount: 1,
                targetValueText: "1개",
                periodText: "계속",
                rewardText: "",
                colorHex: "#E87333",
                roleName: personaName,
                vision: "",
                linkedMemoIDs: []
            ))
        }

        context.insert(AchievementGoalRecord(
            title: visionTitle,
            emoji: draft.visionEmoji,
            cadence: "비전",
            rule: "비전 방향 유지",
            targetCount: 1,
            targetValueText: "1개",
            periodText: "장기",
            rewardText: "",
            colorHex: "#7A52D4",
            roleName: personaName,
            vision: visionText.isEmpty ? visionTitle : visionText,
            linkedMemoIDs: []
        ))
        try saveThrowing()
    }

    // MARK: - 할일 쓰기

    @discardableResult
    func toggleMemoCompletion(id: UUID) throws -> Bool {
        guard let memo = findMemo(id) else { return false }

        let previousCompleted = memo.isCompleted
        let previousChangedAt = memo.completionStateChangedAt
        let previousPinned = memo.isPinned

        memo.isCompletedValue.toggle()
        // 끝낸 일을 계속 위에 붙여둘 이유가 없다.
        if memo.isCompletedValue { memo.isPinned = false }
        memo.updatedAt = Date()
        rescheduleLocalReminder(for: memo)

        do {
            try saveThrowing()
        } catch {
            // 화면과 저장소가 어긋나지 않도록 건드린 값을 전부 되돌린다.
            memo.isCompleted = previousCompleted
            memo.completionStateChangedAt = previousChangedAt
            memo.isPinned = previousPinned
            rescheduleLocalReminder(for: memo)
            throw error
        }
        return memo.isCompletedValue
    }

    func moveMemo(id: UUID, to day: Date) throws {
        guard let memo = findMemo(id) else { return }
        moveSchedule(memo, to: Calendar.current.startOfDay(for: day))
        memo.updatedAt = Date()
        rescheduleLocalReminder(for: memo)
        try saveThrowing()
    }

    func rescheduleMemos(ids: [UUID], targetDays: [Date]) throws {
        guard !ids.isEmpty, !targetDays.isEmpty else { return }
        for (index, id) in ids.enumerated() {
            guard let memo = findMemo(id) else { continue }
            moveSchedule(memo, to: targetDays[index % targetDays.count])
            memo.updatedAt = Date()
            rescheduleLocalReminder(for: memo)
        }
        try saveThrowing()
    }

    func hasLinkedReminders(ids: [UUID]) -> Bool {
        ids.contains { findMemo($0)?.isLinkedToRemindersValue == true }
    }

    func syncLinkedReminders(ids: [UUID]) async -> Int {
        var failed = 0
        for id in ids {
            guard let memo = findMemo(id), memo.isLinkedToRemindersValue else { continue }
            do {
                memo.reminderIdentifier = try await reminders.saveReminder(for: memo)
                rescheduleLocalReminder(for: memo)
                save()
            } catch {
                failed += 1
            }
        }
        return failed
    }

    // MARK: - 부모·자식 잇기

    private func connectChildGoals(_ childGoalIDs: Set<UUID>, to parent: AchievementGoalRecord) {
        guard !childGoalIDs.isEmpty else { return }
        for child in goalRecords() where childGoalIDs.contains(child.id) {
            child.roleName = parent.roleName
            child.vision = parent.vision
            switch parent.cadence {
            case "연간":
                child.yearGoal = parent.title
            case "월간":
                child.yearGoal = parent.yearGoal
                child.quarterGoal = nil
                child.monthGoal = parent.title
            default:
                break
            }
            child.updatedAt = Date()
            connectDescendantGoals(of: child)
        }
    }

    private func connectDescendantGoals(of parent: AchievementGoalRecord) {
        switch parent.cadence {
        case "연간":
            for month in goalRecords() where month.cadence == "월간" && Self.nonEmpty(month.yearGoal) == parent.title {
                month.roleName = parent.roleName
                month.vision = parent.vision
                month.yearGoal = parent.title
                month.quarterGoal = nil
                month.updatedAt = Date()
                connectDescendantGoals(of: month)
            }
        case "월간":
            for week in goalRecords() where week.cadence == "주간" && Self.nonEmpty(week.monthGoal) == parent.title {
                week.roleName = parent.roleName
                week.vision = parent.vision
                week.yearGoal = parent.yearGoal
                week.quarterGoal = nil
                week.monthGoal = parent.title
                week.updatedAt = Date()
            }
        default:
            break
        }
    }

    private func addChildGoal(to parent: AchievementGoalRecord, title: String, emoji: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let childCadence = Self.childCadence(for: parent.cadence), !trimmedTitle.isEmpty else { return }
        let trimmedEmoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        context.insert(AchievementGoalRecord(
            title: trimmedTitle,
            emoji: trimmedEmoji.isEmpty ? Self.defaultEmoji(for: childCadence) : String(trimmedEmoji.prefix(1)),
            cadence: childCadence,
            rule: "",
            targetCount: 1,
            targetValueText: nil,
            periodText: Self.defaultPeriodText(for: childCadence),
            rewardText: "",
            colorHex: parent.colorHex,
            roleName: parent.roleName,
            vision: parent.vision,
            yearGoal: childCadence == "월간" ? parent.title : parent.yearGoal,
            quarterGoal: nil,
            monthGoal: childCadence == "주간" ? parent.title : parent.monthGoal,
            linkedMemoIDs: []
        ))
    }

    /// 제목이 곧 참조라서, 제목을 고치면 그것을 가리키던 자식들을 함께 고쳐야 한다.
    private func syncTitleReferences(oldTitle: String, newTitle: String, cadence: String) {
        guard oldTitle != newTitle,
              !oldTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        for record in goalRecords() {
            switch cadence {
            case "역할" where record.roleName == oldTitle:
                record.roleName = newTitle
            case "비전" where record.vision == oldTitle:
                record.vision = newTitle
            case "연간" where record.yearGoal == oldTitle:
                record.yearGoal = newTitle
            case "월간" where record.monthGoal == oldTitle:
                record.monthGoal = newTitle
            default:
                continue
            }
            record.updatedAt = Date()
        }
    }

    // MARK: - 일정 옮기기

    /// 요일만 바꾸고 **시각은 유지한다.** 오전 9시에 하던 일이 옮긴다고 자정이 되면 안 된다.
    private func moveSchedule(_ record: Todo, to targetDay: Date) {
        switch (record.startDate, record.deadline) {
        case let (startDate?, deadline?):
            let newStart = Self.date(on: targetDay, preservingTimeOf: startDate)
            record.startDate = newStart
            record.deadline = Self.deadlineDate(on: targetDay, preservingTimeOf: deadline, notBefore: newStart)
        case let (startDate?, nil):
            record.startDate = Self.date(on: targetDay, preservingTimeOf: startDate)
        case let (nil, deadline?):
            record.deadline = Self.date(on: targetDay, preservingTimeOf: deadline)
        default:
            record.startDate = Self.date(on: targetDay, preservingTimeOf: Date())
        }
    }

    private static func date(on targetDay: Date, preservingTimeOf source: Date) -> Date {
        let calendar = Calendar.current
        let time = calendar.dateComponents([.hour, .minute, .second], from: source)
        return calendar.date(
            bySettingHour: time.hour ?? 9,
            minute: time.minute ?? 0,
            second: time.second ?? 0,
            of: targetDay
        ) ?? targetDay
    }

    /// 마감이 시작보다 앞서면 그날 끝(23:59)으로 민다.
    private static func deadlineDate(on targetDay: Date, preservingTimeOf source: Date, notBefore start: Date) -> Date {
        let deadline = date(on: targetDay, preservingTimeOf: source)
        guard deadline < start else { return deadline }
        return Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: targetDay) ?? start
    }

    private func rescheduleLocalReminder(for record: Todo) {
        let identifier = "memo.deadline.\(record.id.uuidString)"
        guard !record.isCompletedValue,
              !record.isRecentlyDeleted,
              let fireDate = record.reminderFireDate else {
            notifications.cancel(identifier: identifier)
            return
        }
        notifications.scheduleMemoReminder(
            identifier: identifier,
            title: record.reminderNotificationTitle,
            body: Self.shortText(record.content, limit: 40),
            at: fireDate
        )
    }

    // MARK: - 내부

    private func save() {
        try? context.save()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    private func saveThrowing() throws {
        try context.save()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    private func goalRecords() -> [AchievementGoalRecord] {
        let descriptor = FetchDescriptor<AchievementGoalRecord>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// 보관·최근 삭제는 여기서 떨군다. 화면이 매번 같은 조건을 다시 쓰지 않게.
    private func activeMemoRecords() -> [Todo] {
        let descriptor = FetchDescriptor<Todo>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func findGoal(_ id: UUID) -> AchievementGoalRecord? {
        var descriptor = FetchDescriptor<AchievementGoalRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func findMemo(_ id: UUID) -> Todo? {
        var descriptor = FetchDescriptor<Todo>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func childCadence(for cadence: String) -> String? {
        switch cadence {
        case "연간": return "월간"
        case "월간": return "주간"
        default: return nil
        }
    }

    private static func defaultEmoji(for cadence: String) -> String {
        switch cadence {
        case "연간": return "🏁"
        case "월간": return "📅"
        default: return "🎯"
        }
    }

    private static func defaultPeriodText(for cadence: String) -> String? {
        switch cadence {
        case "연간": return "올해"
        case "월간": return "이번 달"
        case "주간": return "이번 주"
        default: return nil
        }
    }

    /// 첫 줄만, 길면 줄여서. 알림 본문과 역할·비전 제목에 쓴다.
    private static func shortText(_ value: String, limit: Int) -> String {
        let trimmed = value
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
        guard trimmed.count > limit else { return trimmed }
        let index = trimmed.index(trimmed.startIndex, offsetBy: limit)
        return String(trimmed[..<index]) + "…"
    }

    private static func toDetail(_ record: AchievementGoalRecord) -> AchievementGoalDetail {
        AchievementGoalDetail(
            id: record.id,
            title: record.title,
            emoji: record.emoji,
            cadence: record.cadence,
            rule: record.rule,
            targetCount: record.targetCount,
            targetValueText: record.targetValueText,
            periodText: record.periodText,
            dueDate: record.dueDate,
            rewardText: record.rewardText,
            colorHex: record.colorHex,
            roleName: record.roleName,
            vision: record.vision,
            yearGoal: record.yearGoal,
            quarterGoal: record.quarterGoal,
            monthGoal: record.monthGoal,
            linkedMemoIDs: record.linkedMemoIDs,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            completedAt: record.completedAt
        )
    }

    private static func toMemoDetail(_ record: Todo) -> AchievementMemoDetail {
        AchievementMemoDetail(
            id: record.id,
            content: record.content,
            icon: record.icon,
            startDate: record.startDate,
            deadline: record.deadline,
            updatedAt: record.updatedAt,
            isCompleted: record.isCompletedValue
        )
    }
}
