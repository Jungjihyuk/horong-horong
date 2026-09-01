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
    /// Second Brain 섹션. nil 이면 이관 전 기록이라 `resolvedSection` 이 내용으로 판별한다.
    var sectionRaw: String?
    /// 최근 삭제에 들어간 시각. nil 이면 살아 있는 기록.
    var deletedAt: Date?

    init(content: String, icon: String? = nil, section: MemoSection? = nil) {
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
        // 부르는 쪽이 섹션을 안 주면 내용으로 정한다. **nil 로 남기지 않는다.**
        //
        // 화면들이 `#Predicate { $0.sectionRaw == ... }` 로 DB 에서 거르기 때문이다.
        // nil 이면 그 술어에 걸리지 않아 **어느 화면에도 안 나온다** — 다음 실행 때
        // `migrateMemoSections` 가 채워주기 전까지 사라진 것처럼 보인다.
        // 실제로 컴패니언·설정에 섹션 없이 만드는 경로가 셋 있었다.
        self.sectionRaw = (section ?? MemoClassifier.classify(
            content: content,
            startDate: nil,
            deadline: nil
        )).rawValue
        self.deletedAt = nil
    }
}

extension Memo {
    /// 시작·마감을 함께 정한다. **뒤집힌 값이 저장되지 않도록** 한쪽을 옮기면 다른 쪽이 따라온다.
    ///
    /// 방금 고른 쪽을 살리고 반대쪽을 미는 이유는, 사용자가 고른 값을 말없이 버리면
    /// «왜 안 바뀌지» 가 되기 때문이다.
    ///
    /// 규칙을 모델에 두는 이유는 **쓰는 곳이 하나가 아니어서**다. 화면 한 곳에만 두면
    /// 다음 작성자가 그냥 `memo.deadline = …` 을 쓰고 우회한다.
    ///
    /// 뒤집힌 값이 남으면 «마감 − 시작» 이 음수가 되어 소요 시간 통계가 깨진다
    /// (실측 2026-08-20: 시작·마감이 둘 다 있는 완료 할일 68건 중 6건이 역전 상태였다).
    func setStartDate(_ date: Date) {
        startDate = date
        if let deadline, deadline < date { self.deadline = date }
    }

    /// 마감을 시작보다 앞으로 당기면 시작도 함께 당긴다. `setStartDate` 와 같은 사정이다.
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

    var isArchivedValue: Bool {
        get { isArchived == true }
        set { isArchived = newValue }
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
        sectionRaw = section.rawValue
    }

    var todoBucket: TodoBucket {
        TodoBucket.of(
            startDate: startDate,
            deadline: deadline,
            isCompleted: isCompletedValue,
            now: Date()
        )
    }

    var titleLine: String {
        content
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? "제목 없음"
    }
}
