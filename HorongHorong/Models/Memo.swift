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
        set { isCompleted = newValue }
    }

    var isArchivedValue: Bool {
        get { isArchived == true }
        set { isArchived = newValue }
    }

    var isLinkedToRemindersValue: Bool {
        get { isLinkedToReminders == true }
        set { isLinkedToReminders = newValue }
    }
}
