import AppKit
import HorongAI
import HorongAIMLX
import OSLog
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
#if canImport(FoundationModels)
import FoundationModels
#endif

/*
 SwiftData 에서 읽은 것을 화면이 쓸 값 타입으로 바꾼다.
 
  한 번의 렌더에서 쓸 것을 **한 번에** 만든다 — 소비처마다 다시 훑으면 팬아웃이 돌아온다.

 원래 `AchievementViews.swift`(9,854줄) 한 파일에 있었다. 2026-09-03 분할.
 */

enum AchievementDataBuilder {
    static func weekStart(for date: Date, calendar: Calendar = .current) -> Date {
        Constants.mondayWeekStart(for: date, calendar: calendar)
    }

    /// 목표가 화면에 노출되는 주 구간.
    /// 시작은 목표를 만든 주, 끝은 완료한 주(미완료면 이번 주)다.
    /// 저장하지 않고 매번 계산하므로, 완료한 목표에 할 일을 다시 연결하면 구간이 자동으로 이번 주까지 다시 열린다.
    static func goalWeekSpan(for goal: AchievementGoal, now: Date = Date(), calendar: Calendar = .current) -> (start: Date, end: Date) {
        let start = weekStart(for: goal.createdAt, calendar: calendar)
        let isComplete = goal.total > 0 && goal.done >= goal.total
        let rawEnd = isComplete ? weekStart(for: goal.recordDate, calendar: calendar) : weekStart(for: now, calendar: calendar)
        return (start, max(start, rawEnd))
    }

    static func goal(_ goal: AchievementGoal, belongsToWeekStarting weekStart: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let span = goalWeekSpan(for: goal, now: now, calendar: calendar)
        return weekStart >= span.start && weekStart <= span.end
    }

    /// 시작한 주부터 이 주까지 몇 주째인지. 그 주에 시작했으면 1이다.
    static func goalWeekCount(for goal: AchievementGoal, inWeekStarting weekStart: Date, calendar: Calendar = .current) -> Int {
        let start = goalWeekSpan(for: goal, calendar: calendar).start
        let weeks = calendar.dateComponents([.weekOfYear], from: start, to: weekStart).weekOfYear ?? 0
        return max(1, weeks + 1)
    }

    static func weekRangeText(forWeekStarting weekStart: Date, calendar: Calendar = .current) -> String {
        let end = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일"
        return "\(formatter.string(from: weekStart)) – \(formatter.string(from: end))"
    }

    @MainActor
    static func goals(from records: [AchievementGoalRecord], memos: [Memo]) -> [AchievementGoal] {
        let memoByID = Dictionary(uniqueKeysWithValues: memos.map { ($0.id, $0) })
        func nonEmpty(_ value: String?) -> String? {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }
        func childCadence(for cadence: String) -> String? {
            switch cadence {
            case "연간": return "월간"
            case "월간": return "주간"
            default: return nil
            }
        }
        func childRecords(for record: AchievementGoalRecord) -> [AchievementGoalRecord] {
            guard let childCadence = childCadence(for: record.cadence) else { return [] }
            return records.filter { child in
                guard child.cadence == childCadence else { return false }
                switch record.cadence {
                case "연간":
                    return nonEmpty(child.yearGoal) == record.title
                case "월간":
                    return nonEmpty(child.monthGoal) == record.title
                default:
                    return false
                }
            }
        }
        func directProgress(for record: AchievementGoalRecord) -> (done: Int, total: Int) {
            let linkedMemos = record.linkedMemoIDs.compactMap { memoByID[$0] }
            guard !linkedMemos.isEmpty else { return (0, 0) }
            return (linkedMemos.filter(\.isCompletedValue).count, max(1, record.targetCount))
        }
        func progress(for record: AchievementGoalRecord, visited: Set<UUID> = []) -> (done: Int, total: Int) {
            guard !visited.contains(record.id) else {
                return directProgress(for: record)
            }
            let children = childRecords(for: record)
            guard !children.isEmpty else {
                return directProgress(for: record)
            }
            let nextVisited = visited.union([record.id])
            let childProgresses = children.map { progress(for: $0, visited: nextVisited) }
            let completedChildren = childProgresses.filter { $0.total > 0 && $0.done >= $0.total }.count
            return (completedChildren, children.count)
        }
        func descendantMemoIDs(for record: AchievementGoalRecord, visited: Set<UUID> = []) -> [UUID] {
            guard !visited.contains(record.id) else {
                return record.linkedMemoIDs
            }
            let nextVisited = visited.union([record.id])
            let childMemoIDs = childRecords(for: record).flatMap { descendantMemoIDs(for: $0, visited: nextVisited) }
            return Array(Set(record.linkedMemoIDs + childMemoIDs))
        }
        return records.map { record in
            let sourceMemoIDs = descendantMemoIDs(for: record)
            let linkedMemos = sourceMemoIDs.compactMap { memoByID[$0] }
                .sorted { memoDate($0) < memoDate($1) }
            let recordDate = linkedMemos
                .filter(\.isCompletedValue)
                .map(memoDate)
                .max() ?? record.updatedAt
            let todos = linkedMemos.map { memo in
                AchievementTodo(
                    id: memo.id,
                    text: shortText(memo.content, limit: 28),
                    when: dateRangeText(for: memo),
                    detail: todoDetail(for: memo),
                    status: todoStatus(for: memo)
                )
            }
            let goalProgress = progress(for: record)
            let done = goalProgress.total > 0 ? min(goalProgress.done, goalProgress.total) : 0
            let total = goalProgress.total
            // 달성을 **사건으로** 남긴다. 여기가 달성 여부를 아는 유일한 자리다 —
            // `done`·`total` 은 지금 남아 있는 할일로부터 계산되므로, 나중에 할일을 더하거나
            // 지우면 답이 바뀐다. 처음 참이 된 순간을 찍어 두지 않으면 그 사실을 잃는다.
            //
            // 한 번 찍은 값은 되돌리지 않는다. 달성이 풀리는 일(할일 추가)은 있어도
            // «그때 달성했었다» 는 사실은 변하지 않는다.
            if total > 0, done >= total, record.completedAt == nil {
                record.completedAt = Date()
            }
            return AchievementGoal(
                id: record.id,
                emoji: record.emoji,
                title: shortText(record.title, limit: 40),
                cadence: record.cadence,
                rule: displayRule(for: record, total: total),
                done: min(done, total),
                total: total,
                reward: AchievementReward(
                    amount: record.rewardText.isEmpty ? AchievementReward.emptyAmount : record.rewardText
                ),
                color: color(from: record.colorHex),
                todos: todos,
                roleName: record.roleName,
                vision: record.vision,
                yearGoal: record.yearGoal,
                quarterGoal: record.quarterGoal,
                monthGoal: record.monthGoal,
                recordDate: recordDate,
                createdAt: record.createdAt,
                dueDate: record.dueDate,
                sourceMemoIDs: sourceMemoIDs
            )
        }
    }

    static func roles(from goals: [AchievementGoal]) -> [AchievementRole] {
        var seen = Set<String>()
        let personaNames = Set(goals.filter { $0.cadence == "역할" }.map(\.title))
        return goals.compactMap { goal in
            guard !goal.roleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            guard personaNames.contains(goal.roleName) else {
                return nil
            }
            guard seen.insert(goal.roleName).inserted else { return nil }
            let personaGoal = goals.first { $0.cadence == "역할" && $0.title == goal.roleName }
            let roleGoals = goals.filter { $0.roleName == goal.roleName }
            let visionGoal = roleGoals.first { $0.cadence == "비전" }
            let roleVision = [
                visionGoal?.vision,
                visionGoal?.title,
                roleGoals.first { !$0.vision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?.vision,
                goal.vision,
            ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
            return AchievementRole(id: goal.roleName, emoji: personaGoal?.emoji ?? goal.emoji, name: goal.roleName, vision: roleVision)
        }
    }

    static func timeline(for goal: AchievementGoal, memos: [Memo], weekStarting weekStart: Date, referenceDate: Date = Date()) -> [AchievementTimelineItem] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: weekStart)
        let linked = memos.filter { goal.sourceMemoIDs.contains($0.id) }
        let completedCount = linked.filter(\.isCompletedValue).count
        let lastCompletedDate = linked.filter(\.isCompletedValue).compactMap(timelineDate).max()

        return (0..<7).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: start) ?? start
            let dayMemos = linked
                .filter { memo in
                    guard let date = timelineDate(memo) else { return false }
                    return calendar.isDate(date, inSameDayAs: day)
                }
                .sorted {
                    (timelineDate($0) ?? .distantFuture) < (timelineDate($1) ?? .distantFuture)
                }
            let isLastDay = offset == 6
            let hasReward = isLastDay && !goal.reward.amount.isEmpty
                && goal.reward.amount != AchievementReward.emptyAmount
            let isCompletedDay = dayMemos.contains(where: \.isCompletedValue)
            let isFutureDay = !isCompletedDay && calendar.startOfDay(for: day) > calendar.startOfDay(for: referenceDate)
            let topLabel: String?
            if hasReward {
                topLabel = goal.reward.amount
            } else if let lastCompletedDate, calendar.isDate(lastCompletedDate, inSameDayAs: day) {
                topLabel = "\(min(completedCount, goal.total))/\(goal.total) 달성"
            } else {
                topLabel = nil
            }
            return AchievementTimelineItem(
                date: day,
                weekday: weekday(day),
                topLabel: topLabel,
                todos: dayMemos.map { memo in
                    AchievementTimelineTodo(
                        id: memo.id,
                        memoID: memo.id,
                        title: shortText(memo.content, limit: 200),
                        meta: todoMetaText(for: memo),
                        isCompleted: memo.isCompletedValue,
                        isFuture: todoStatus(for: memo, referenceDate: referenceDate) == .future,
                        sortDate: timelineDate(memo),
                        hasStartTime: memo.startDate != nil
                    )
                },
                isCompleted: isCompletedDay || hasReward,
                isFuture: isFutureDay,
                isReward: hasReward
            )
        }
    }

    static func timeline(
        for goals: [AchievementGoal],
        memos: [Memo],
        weekStarting weekStart: Date,
        referenceDate: Date = Date(),
        sortOrder: Constants.AchievementTimelineSortOrder = .ascending
    ) -> [AchievementTimelineItem] {
        guard !goals.isEmpty else { return [] }

        let timelines = goals.map { goal in
            (goal: goal, items: timeline(for: goal, memos: memos, weekStarting: weekStart, referenceDate: referenceDate))
        }

        return (0..<7).map { index in
            let dayItems = timelines.compactMap { timeline in
                timeline.items.indices.contains(index) ? (timeline.goal, timeline.items[index]) : nil
            }
            let baseItem = dayItems.first?.1
            let todos = sortedTodos(
                dayItems.flatMap { goal, item in
                    item.todos.map { todo in
                        AchievementTimelineTodo(
                            id: UUID(),
                            memoID: todo.memoID,
                            title: "\(goal.emoji) \(todo.title)",
                            meta: todo.meta,
                            isCompleted: todo.isCompleted,
                            isFuture: todo.isFuture,
                            sortDate: todo.sortDate,
                            hasStartTime: todo.hasStartTime
                        )
                    }
                },
                by: sortOrder
            )

            return AchievementTimelineItem(
                date: baseItem?.date ?? Date(),
                weekday: baseItem?.weekday ?? "",
                topLabel: nil,
                todos: todos,
                isCompleted: dayItems.contains { $0.1.isCompleted },
                isFuture: !dayItems.contains { $0.1.isCompleted } && (baseItem?.isFuture ?? false),
                isReward: false
            )
        }
    }

    static func activeMemos(_ memos: [Memo]) -> [Memo] {
        memos.filter { !$0.isArchivedValue && !$0.isRecentlyDeleted }
    }

    static func displayRule(for record: AchievementGoalRecord, total: Int) -> String {
        let criterion = record.rule.trimmingCharacters(in: .whitespacesAndNewlines)
        if !criterion.isEmpty {
            return criterion
        }
        let target = record.targetValueText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let period = record.periodText?.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            target?.isEmpty == false ? target : (total > 0 ? "메모 \(total)개 완료" : nil),
            period?.isEmpty == false ? period : record.cadence,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    static func memoDate(_ memo: Memo) -> Date {
        memo.deadline ?? memo.startDate ?? memo.updatedAt
    }

    /// 카드가 어느 요일 칸에 놓일지, 칸 안에서 몇 번째로 놓일지를 함께 정하는 기준.
    /// 타임라인은 «언제 하는 일인지»를 읽는 화면이라 시작 시각을 먼저 본다.
    private static func timelineDate(_ memo: Memo) -> Date? {
        memo.startDate ?? memo.deadline
    }

    /// 하루 컬럼 안에서 할일 카드가 위→아래로 쌓이는 순서.
    ///
    /// 시작 시각이 있는 일이 항상 위, 마감만 있는 일이 그 아래 그룹으로 간다.
    /// 시작 시각과 마감 시각은 의미가 다른 시각이라 한 줄에 섞으면 같은 축처럼 읽히기 때문이고,
    /// 이 계층은 오름/내림·완료 기준 선택과 무관하게 고정이다. 선택한 정렬은 각 그룹 안에서만 적용된다.
    ///
    /// 시각이 같으면 제목으로 한 번 더 가른다. `sorted(by:)` 는 안정 정렬이 아니라서
    /// 이 동점 처리가 없으면 다시 그릴 때마다 같은 시각 카드들의 위아래가 뒤바뀐다.
    private static func sortedTodos(
        _ todos: [AchievementTimelineTodo],
        by order: Constants.AchievementTimelineSortOrder
    ) -> [AchievementTimelineTodo] {
        func ascending(_ lhs: AchievementTimelineTodo, _ rhs: AchievementTimelineTodo) -> Bool {
            let left = lhs.sortDate ?? .distantFuture
            let right = rhs.sortDate ?? .distantFuture
            return left == right ? lhs.title < rhs.title : left < right
        }

        func withinGroup(_ lhs: AchievementTimelineTodo, _ rhs: AchievementTimelineTodo) -> Bool {
            switch order {
            case .ascending:
                return ascending(lhs, rhs)
            case .descending:
                let left = lhs.sortDate ?? .distantPast
                let right = rhs.sortDate ?? .distantPast
                return left == right ? lhs.title < rhs.title : left > right
            case .completedFirst:
                return lhs.isCompleted == rhs.isCompleted ? ascending(lhs, rhs) : lhs.isCompleted
            case .completedLast:
                return lhs.isCompleted == rhs.isCompleted ? ascending(lhs, rhs) : rhs.isCompleted
            }
        }

        return todos.sorted { lhs, rhs in
            lhs.hasStartTime == rhs.hasStartTime ? withinGroup(lhs, rhs) : lhs.hasStartTime
        }
    }

    static func dateRangeText(for memo: Memo) -> String {
        switch (memo.startDate, memo.deadline) {
        case let (start?, deadline?):
            return "\(shortDate(start)) - \(shortDate(deadline))"
        case let (start?, nil):
            return "시작 \(shortDate(start))"
        case let (nil, deadline?):
            return "마감 \(shortDate(deadline))"
        default:
            return ""
        }
    }

    static func todoMetaText(for memo: Memo) -> String {
        let dateText = dateRangeText(for: memo)
        let detail = todoDetail(for: memo)
        if dateText.isEmpty {
            return detail
        }
        if detail.isEmpty {
            return dateText
        }
        return "\(dateText) · \(detail)"
    }

    static func todoDetail(for memo: Memo, referenceDate: Date = Date()) -> String {
        if memo.isCompletedValue {
            return "완료"
        }
        guard memo.startDate != nil || memo.deadline != nil else {
            return ""
        }
        if Calendar.current.startOfDay(for: memoDate(memo)) > Calendar.current.startOfDay(for: referenceDate) {
            return "예정"
        }
        return ""
    }

    static func todoStatus(for memo: Memo, referenceDate: Date = Date()) -> AchievementTodoStatus {
        if memo.isCompletedValue {
            return .done
        }
        if Calendar.current.startOfDay(for: memoDate(memo)) > Calendar.current.startOfDay(for: referenceDate) {
            return .future
        }
        return .pending
    }

    static func shortText(_ value: String, limit: Int) -> String {
        let trimmed = value
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return "\(trimmed.prefix(limit))..."
    }

    @MainActor
    static func color(from hex: String) -> Color {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else {
            return PopoverChrome.accent
        }
        return Color(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255
        )
    }

    private static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "E HH:mm"
        return formatter.string(from: date)
    }

    private static func weekday(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "E"
        return formatter.string(from: date)
    }
}
