import Foundation
import SwiftData

/// `ReminderImportRepository` 의 SwiftData 구현.
@MainActor
final class SwiftDataReminderImportRepository: ReminderImportRepository {
    private let context: ModelContext
    private let notifications: NotificationManager

    init(context: ModelContext, notifications: NotificationManager = .shared) {
        self.context = context
        self.notifications = notifications
    }

    func memosLinkedToUnselectedCalendars(selectedCalendarIDs: Set<String>) -> [ImportedReminderMemo] {
        allMemos().compactMap { memo in
            guard memo.isLinkedToRemindersValue,
                  memo.reminderIdentifier != nil,
                  let calendarID = memo.reminderCalendarIdentifier,
                  !selectedCalendarIDs.contains(calendarID) else {
                return nil
            }
            return ImportedReminderMemo(
                id: memo.id,
                content: memo.content,
                reminderCalendarIdentifier: calendarID
            )
        }
    }

    @discardableResult
    func importReminders(_ items: [ReminderListItem]) throws -> Int {
        let history = allMemos()
        let existing = Set(history.compactMap(\.reminderIdentifier))
        var imported = 0

        for item in items where !item.isCompleted && !existing.contains(item.id) {
            let memo = Memo(content: Self.content(from: item), icon: MemoIcon.defaultIcon)
            let schedule = Self.schedule(for: item, history: history)
            memo.startDate = schedule.start
            memo.deadline = schedule.deadline
            memo.reminderIdentifier = item.id
            memo.reminderCalendarIdentifier = item.calendarIdentifier
            memo.isLinkedToRemindersValue = true
            context.insert(memo)
            imported += 1
        }

        try context.save()
        return imported
    }

    func deleteImportedMemos(ids: [UUID]) throws {
        for id in ids {
            guard let memo = find(id) else { continue }
            // 지운 메모의 마감 알림이 남으면 없는 할 일이 울린다.
            notifications.cancel(identifier: "memo.deadline.\(memo.id.uuidString)")
            context.delete(memo)
        }
        try context.save()
    }

    // MARK: - 내부

    /// 시작·마감이 둘 다 있으면 그대로 쓴다. 하나뿐이면 그 시각을 기준으로,
    /// **지난 기록에서 추정한 소요 시간**만큼 뒤를 마감으로 잡는다.
    private static func schedule(
        for item: ReminderListItem,
        history: [Memo]
    ) -> (start: Date?, deadline: Date?) {
        if let start = item.startDate, let due = item.dueDate, due > start {
            return (start, due)
        }
        guard let anchor = item.dueDate ?? item.startDate else {
            return (nil, nil)
        }
        let duration = MemoDurationEstimator.estimate(title: item.title, history: history)
        return (anchor, anchor.addingTimeInterval(duration))
    }

    /// 제목 · 메모 · 링크를 줄바꿈으로 잇는다. 링크가 이미 본문에 있으면 또 넣지 않는다.
    private static func content(from item: ReminderListItem) -> String {
        var lines = [item.title]
        if let notes = item.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            lines.append(notes)
        }
        if let url = item.url?.absoluteString, !lines.contains(where: { $0.contains(url) }) {
            lines.append(url)
        }
        return lines.joined(separator: "\n")
    }

    private func allMemos() -> [Memo] {
        let descriptor = FetchDescriptor<Memo>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    private func find(_ id: UUID) -> Memo? {
        var descriptor = FetchDescriptor<Memo>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
