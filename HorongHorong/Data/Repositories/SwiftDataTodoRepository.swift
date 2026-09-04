import Foundation
import SwiftData

/// `TodoRepository` 의 SwiftData 구현.
///
/// 저장·미리알림 연동·로컬 알림 예약을 한곳에서 한다. **쓰기 경로마다 «저장했으면 알림도
/// 다시 건다» 를 기억할 필요가 없게** `touch(_:)` 하나를 통과시킨다.
@MainActor
final class SwiftDataTodoRepository: TodoRepository {
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

    // MARK: - 읽기

    func activeTodos(matching query: String) throws -> [TodoItem] {
        try fetch(Self.activeSection, matching: query)
    }

    func recentlyDeleted(matching query: String) throws -> [TodoItem] {
        try fetch(Self.deletedSection, matching: query, sortBy: [SortDescriptor(\.deletedAt, order: .reverse)])
    }

    func todo(id: UUID) throws -> TodoItem? {
        try find(id).map(Self.toItem)
    }

    func linkableTodos(matching query: String) throws -> [TodoItem] {
        try fetch(
            Self.activeSection,
            matching: query,
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
    }

    // MARK: - 쓰기

    @discardableResult
    func add(title: String) throws -> TodoItem {
        let record = Todo(content: title)
        record.startDate = Self.daytime(Date(), hour: 9)
        context.insert(record)
        try touch(record)
        return Self.toItem(record)
    }

    @discardableResult
    func addTodayTask(content: String, icon: String?) throws -> TodoItem {
        let record = Todo(content: content, icon: icon)
        record.startDate = Date()
        context.insert(record)
        try touch(record)
        notifications.cancel(identifier: Constants.todayPlanningReminderNotificationIdentifier)
        return Self.toItem(record)
    }

    func updateContent(id: UUID, content: String) throws {
        try change(id) { $0.content = content }
    }

    func setCompleted(id: UUID, isCompleted: Bool) throws {
        try change(id, syncLinkedReminder: true) { memo in
            memo.isCompletedValue = isCompleted
            // 끝낸 일이 목록 위에 고정된 채 남으면 «오늘 할 일» 이 가려진다.
            if isCompleted { memo.isPinned = false }
        }
    }

    func setSchedule(id: UUID, startDate: Date?, deadline: Date?) throws {
        try change(id, syncLinkedReminder: true) { memo in
            memo.startDate = startDate
            memo.deadline = deadline.map { end in
                startDate.map { max($0, end) } ?? end
            }
        }
    }

    func place(id: UUID, into bucket: TodoBucket, now: Date) throws {
        try change(id, syncLinkedReminder: true) { memo in
            memo.deletedAt = nil
            let placed = TodoBucket.placement(
                into: bucket,
                startDate: memo.startDate,
                deadline: memo.deadline,
                isCompleted: memo.isCompletedValue,
                now: now
            )
            memo.isCompletedValue = placed.isCompleted
            if placed.isCompleted { memo.isPinned = false }
            memo.startDate = placed.startDate
            memo.deadline = placed.deadline
            if let start = memo.startDate, let deadline = memo.deadline, deadline < start {
                memo.deadline = start
            }
        }
    }

    func setReminderList(id: UUID, listID: String) throws {
        try change(id, syncLinkedReminder: true) { $0.reminderCalendarIdentifier = listID }
    }

    func setPinned(id: UUID, isPinned: Bool) throws {
        try change(id) { $0.isPinned = isPinned }
    }

    func setIcon(id: UUID, icon: String) throws {
        try change(id) { $0.icon = icon }
    }

    // MARK: - 미리알림

    func reminderLists() async throws -> [ReminderListOption] {
        try await reminders.reminderLists()
    }

    func linkReminder(id: UUID) async throws {
        guard let memo = try find(id) else { return }
        do {
            memo.reminderIdentifier = try await reminders.saveReminder(for: memo)
            memo.isLinkedToRemindersValue = true
            try touch(memo)
        } catch {
            // 연결에 실패했는데 «연동됨» 으로 남으면 다음 저장마다 없는 미리알림을 고치려 든다.
            memo.isLinkedToRemindersValue = false
            try? context.save()
            throw error
        }
    }

    func syncReminder(id: UUID) async throws {
        guard let memo = try find(id), memo.isLinkedToRemindersValue else { return }
        memo.reminderIdentifier = try await reminders.saveReminder(for: memo)
        try touch(memo)
    }

    func unlinkReminder(id: UUID) throws {
        guard let memo = try find(id) else { return }
        try reminders.removeReminder(for: memo)
        memo.isLinkedToRemindersValue = false
        memo.reminderIdentifier = nil
        try touch(memo)
    }

    // MARK: - 삭제

    func moveToRecentlyDeleted(id: UUID) throws {
        guard let memo = try find(id) else { return }
        detachReminders(memo)
        memo.deletedAt = Date()
        try touch(memo)
    }

    func restore(id: UUID) throws {
        try change(id) { $0.deletedAt = nil }
    }

    func deletePermanently(id: UUID) throws {
        guard let memo = try find(id) else { return }
        detachReminders(memo)
        context.delete(memo)
        try context.save()
    }

    func emptyRecentlyDeleted() throws {
        for record in try context.fetch(FetchDescriptor<Todo>(predicate: Self.deletedSection)) {
            detachReminders(record)
            context.delete(record)
        }
        try context.save()
    }

    // MARK: - 술어

    /// 살아 있는 할 일. 보관·최근 삭제는 SQL 에서 떨군다 —
    /// 예전에는 전량을 가져와 Swift 에서 걸렀다.
    private static let activeSection = #Predicate<Todo> {
        $0.deletedAt == nil
    }

    private static let deletedSection = #Predicate<Todo> {
        $0.deletedAt != nil
    }

    // MARK: - 내부

    private func fetch(
        _ predicate: Predicate<Todo>,
        matching query: String,
        sortBy: [SortDescriptor<Todo>] = [SortDescriptor(\.createdAt, order: .reverse)]
    ) throws -> [TodoItem] {
        let items = try context.fetch(FetchDescriptor<Todo>(predicate: predicate, sortBy: sortBy))
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items.map(Self.toItem) }
        // `localizedCaseInsensitiveContains` 는 SQL 로 번역되지 않아 여기서 거른다.
        return items
            .filter { $0.content.localizedCaseInsensitiveContains(trimmed) }
            .map(Self.toItem)
    }

    private func find(_ id: UUID) throws -> Todo? {
        var descriptor = FetchDescriptor<Todo>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func change(_ id: UUID, syncLinkedReminder: Bool = false, _ edit: (Todo) -> Void) throws {
        guard let record = try find(id) else { return }
        edit(record)
        try touch(record, syncLinkedReminder: syncLinkedReminder)
    }

    /// 고친 뒤 `updatedAt` 을 올리고, 로컬 알림을 다시 걸고, 저장한다.
    ///
    /// 미리알림 앱 쪽 반영은 시간이 걸려 `Task` 로 뗀다 — 실패해도 저장은 이미 끝나 있다.
    private func touch(_ record: Todo, syncLinkedReminder: Bool = false) throws {
        record.updatedAt = Date()
        rescheduleLocalReminder(for: record)
        try context.save()
        guard syncLinkedReminder, record.isLinkedToRemindersValue else { return }
        let id = record.id
        Task { @MainActor [weak self] in
            try? await self?.syncReminder(id: id)
        }
    }

    private func rescheduleLocalReminder(for record: Todo) {
        let identifier = Self.localReminderIdentifier(for: record.id)
        guard !record.isCompletedValue,
              !record.isRecentlyDeleted,
              let fireDate = record.reminderFireDate else {
            notifications.cancel(identifier: identifier)
            return
        }
        notifications.scheduleMemoReminder(
            identifier: identifier,
            title: record.reminderNotificationTitle,
            body: Self.toItem(record).displayTitle,
            at: fireDate
        )
    }

    /// 지우기 전에 걸어둔 알림·미리알림을 떼어낸다. 안 떼면 없는 할 일의 알림이 울린다.
    private func detachReminders(_ record: Todo) {
        notifications.cancel(identifier: Self.localReminderIdentifier(for: record.id))
        guard record.isLinkedToRemindersValue else { return }
        try? reminders.removeReminder(for: record)
        record.isLinkedToRemindersValue = false
        record.reminderIdentifier = nil
    }

    private static func localReminderIdentifier(for id: UUID) -> String {
        "memo.deadline.\(id.uuidString)"
    }

    private static func daytime(_ day: Date, hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
    }

    private static func toItem(_ record: Todo) -> TodoItem {
        TodoItem(
            id: record.id,
            content: record.content,
            startDate: record.startDate,
            deadline: record.deadline,
            isCompleted: record.isCompletedValue,
            deletedAt: record.deletedAt,
            isLinkedToReminders: record.isLinkedToRemindersValue,
            reminderCalendarIdentifier: record.reminderCalendarIdentifier,
            icon: record.icon,
            isPinned: record.isPinned,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
    }
}
