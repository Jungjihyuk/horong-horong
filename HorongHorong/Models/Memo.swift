import Foundation
import SwiftData

@Model
final class Memo {
    var id: UUID
    var content: String
    var createdAt: Date
    var updatedAt: Date
    var isPinned: Bool
    var isCompleted: Bool?
    var completionStateChangedAt: Date?
    var isArchived: Bool?
    var icon: String?
    var startDate: Date?
    var deadline: Date?
    var reminderOffsetMinutes: Int?
    var reminderIdentifier: String?
    var reminderCalendarIdentifier: String?
    var isLinkedToReminders: Bool?

    init(content: String, icon: String? = nil) {
        self.id = UUID()
        self.content = content
        self.createdAt = Date()
        self.updatedAt = Date()
        self.isPinned = false
        self.isCompleted = false
        self.completionStateChangedAt = nil
        self.isArchived = false
        self.icon = icon
        self.startDate = nil
        self.deadline = nil
        self.reminderOffsetMinutes = nil
        self.reminderIdentifier = nil
        self.reminderCalendarIdentifier = nil
        self.isLinkedToReminders = false
    }
}

extension Memo {
    var isCompletedValue: Bool {
        get { isCompleted == true }
        set { setCompleted(newValue, at: Date()) }
    }

    func setCompleted(_ value: Bool, at changedAt: Date) {
        guard isCompletedValue != value else {
            isCompleted = value
            return
        }
        isCompleted = value
        completionStateChangedAt = changedAt
    }

    var isArchivedValue: Bool {
        get { isArchived == true }
        set { isArchived = newValue }
    }

    var isLinkedToRemindersValue: Bool {
        get { isLinkedToReminders == true }
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
        isReminderDeadlineBased ? "메모 마감 알림" : "메모 시작 알림"
    }
}
