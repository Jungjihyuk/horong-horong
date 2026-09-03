import Foundation
import SwiftData

/// Second Brain 기록 영속 모델 (구 Memo 모델의 신규 스키마 대체).
///
/// '메모'에서 'Second Brain / 기록'으로의 확장을 담는 핵심 영속 타입이다.
/// `AGENTS.md` 네이밍 규칙에 따라 `<Name>Record` 형태를 따른다.
@Model
final class SecondBrainRecord {
    var id: UUID
    var content: String
    var createdAt: Date
    var updatedAt: Date
    var isPinned: Bool
    var isCompleted: Bool?
    var completionStateChangedAt: Date?
    /// 더 이상 쓰지 않는다 (레거시 필드 보존용).
    var isArchived: Bool?
    var icon: String?
    var startDate: Date?
    var deadline: Date?
    var reminderOffsetMinutes: Int?
    var reminderIdentifier: String?
    var reminderCalendarIdentifier: String?
    var isLinkedToReminders: Bool?
    /// Second Brain 섹션 (todo, quickNote, reference, diary 등).
    var sectionRaw: String?
    /// 최근 삭제에 들어간 시각. nil 이면 살아 있는 기록.
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        content: String,
        icon: String? = nil,
        section: MemoSection? = nil,
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
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPinned = isPinned
        self.isCompleted = isCompleted
        self.completionStateChangedAt = completionStateChangedAt
        self.isArchived = false
        self.icon = icon
        self.startDate = startDate
        self.deadline = deadline
        self.reminderOffsetMinutes = reminderOffsetMinutes
        self.reminderIdentifier = reminderIdentifier
        self.reminderCalendarIdentifier = reminderCalendarIdentifier
        self.isLinkedToReminders = isLinkedToReminders
        self.sectionRaw = (section ?? MemoClassifier.classify(
            content: content,
            startDate: startDate,
            deadline: deadline
        )).rawValue
        self.deletedAt = deletedAt
    }
}

extension SecondBrainRecord {
    func setStartDate(_ date: Date) {
        startDate = date
        if let deadline, deadline < date { self.deadline = date }
    }

    func setDeadline(_ date: Date) {
        deadline = date
        if let startDate, date < startDate { self.startDate = date }
    }

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

    var isRecentlyDeleted: Bool {
        deletedAt != nil
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
        isReminderDeadlineBased ? "할 일 마감 알림" : "할 일 시작 알림"
    }

    var resolvedSection: MemoSection {
        if let sectionRaw, let section = MemoSection(rawValue: sectionRaw) {
            return section
        }
        return MemoClassifier.classify(
            content: content,
            startDate: startDate,
            deadline: deadline
        )
    }

    func assignSection(_ section: MemoSection) {
        self.sectionRaw = section.rawValue
    }

    var todoBucket: TodoBucket {
        TodoBucket.of(
            startDate: startDate,
            deadline: deadline,
            isCompleted: isCompletedValue,
            now: Date()
        )
    }
}
