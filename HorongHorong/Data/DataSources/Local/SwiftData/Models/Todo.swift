import Foundation
import SwiftData

/// 할 일(Todo) 영속 모델.
///
/// SQLite 테이블: `ZTODO`
@Model
final class Todo {
    var id: UUID
    var content: String
    var icon: String?
    var createdAt: Date
    var updatedAt: Date
    var isPinned: Bool
    var isCompleted: Bool
    var completionStateChangedAt: Date?
    var startDate: Date?
    var deadline: Date?
    var reminderOffsetMinutes: Int?
    var reminderIdentifier: String?
    var reminderCalendarIdentifier: String?
    var isLinkedToReminders: Bool
    var deletedAt: Date?
    var isArchived: Bool = false

    init(
        id: UUID = UUID(),
        content: String = "",
        icon: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isPinned: Bool = false,
        isCompleted: Bool = false,
        completionStateChangedAt: Date? = nil,
        startDate: Date? = nil,
        deadline: Date? = nil,
        reminderOffsetMinutes: Int? = nil,
        reminderIdentifier: String? = nil,
        reminderCalendarIdentifier: String? = nil,
        isLinkedToReminders: Bool = false,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.content = content
        self.icon = icon
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPinned = isPinned
        self.isCompleted = isCompleted
        self.completionStateChangedAt = completionStateChangedAt
        self.startDate = startDate
        self.deadline = deadline
        self.reminderOffsetMinutes = reminderOffsetMinutes
        self.reminderIdentifier = reminderIdentifier
        self.reminderCalendarIdentifier = reminderCalendarIdentifier
        self.isLinkedToReminders = isLinkedToReminders
        self.deletedAt = deletedAt
    }
}

extension Todo {
    var isRecentlyDeleted: Bool {
        deletedAt != nil
    }

    func setStartDate(_ date: Date) {
        startDate = date
        if let deadline, deadline < date { self.deadline = date }
    }

    func setDeadline(_ date: Date) {
        deadline = date
        if let startDate, date < startDate { self.startDate = date }
    }

    var isCompletedValue: Bool {
        get { isCompleted }
        set { setCompleted(newValue, at: Date()) }
    }

    func setCompleted(_ value: Bool, at changedAt: Date = Date()) {
        guard isCompleted != value else { return }
        isCompleted = value
        completionStateChangedAt = changedAt
        updatedAt = changedAt
    }

    var isLinkedToRemindersValue: Bool {
        get { isLinkedToReminders }
        set { isLinkedToReminders = newValue }
    }

    /// 알림 기준 시각. "마감 시간"(offset 0)만 마감일을 쓰고,
    /// 사전 알림(10분·1시간·1일 전)은 시작일을 기준으로 한다. 시작일이 없으면 마감일로 대체한다.
    var reminderBaseDate: Date? {
        guard let offset = reminderOffsetMinutes else { return nil }
        return offset == 0 ? deadline : (startDate ?? deadline)
    }

    var isReminderDeadlineBased: Bool {
        reminderOffsetMinutes == 0 || startDate == nil
    }

    var reminderFireDate: Date? {
        guard let offset = reminderOffsetMinutes, let base = reminderBaseDate else { return nil }
        return base.addingTimeInterval(TimeInterval(-offset * 60))
    }

    var reminderNotificationTitle: String {
        isReminderDeadlineBased ? "할 일 마감 알림" : "할 일 시작 알림"
    }

    var reminderDueDate: Date? {
        deadline ?? startDate
    }

    var reminderTriggerDate: Date? {
        guard let reminderDueDate else { return nil }
        guard let reminderOffsetMinutes else { return reminderDueDate }
        return Calendar.current.date(
            byAdding: .minute,
            value: -reminderOffsetMinutes,
            to: reminderDueDate
        )
    }

    func todoBucket(now: Date = Date(), calendar: Calendar = .current) -> TodoBucket {
        TodoBucket.of(
            startDate: startDate,
            deadline: deadline,
            isCompleted: isCompletedValue,
            now: now,
            calendar: calendar
        )
    }
}

