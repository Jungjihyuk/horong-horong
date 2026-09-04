import AppKit
import HorongAI
import HorongAIMLX
import OSLog
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

/// 저장된 값을 화면이 쓸 모습으로 조립한다.
///
/// **표현 계층에 있는 이유**: 결과인 `AchievementGoal` 이 `Color` 를 들고 있다.
/// 입력은 `Domain` 의 값 타입이라 SwiftData 를 import 하지 않는다.
enum AchievementDataBuilder {
    static func weekStart(for date: Date, calendar: Calendar = .current) -> Date {
        Constants.mondayWeekStart(for: date, calendar: calendar)
    }

    /// 목표가 화면에 노출되는 주 구간.
    /// 시작은 목표를 만든 주, 끝은 완료한 주(열려 있으면 이번 주)다.
    /// 저장하지 않고 매번 계산하므로, 완료한 목표에 할 일을 다시 연결하면 구간이 자동으로 이번 주까지 다시 열린다.
    static func goalWeekSpan(for goal: AchievementGoal, now: Date = Date(), calendar: Calendar = .current) -> (start: Date, end: Date) {
        let start = weekStart(for: goal.createdAt, calendar: calendar)
        let isComplete = goal.total > 0 && goal.done >= goal.total
        // 실패·접음은 마감이 지난 뒤 결정할 수 있으므로 버튼을 누른 시각으로 귀속하면
        // 지난 목표가 정산한 주의 목표처럼 보인다. 명시한 마감일, 없으면 암묵적 마감의
        // 기준인 생성일로 돌려서 실제 성적이 속한 주에서 끝낸다.
        let closingMoment: Date?
        if goal.closedAt != nil {
            closingMoment = goal.dueDate ?? goal.createdAt
        } else {
            closingMoment = isComplete ? goal.recordDate : nil
        }
        let rawEnd = weekStart(for: closingMoment ?? now, calendar: calendar)
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
    static func goals(from records: [AchievementGoalDetail], memos: [AchievementMemoDetail]) -> [AchievementGoal] {
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
        func childRecords(for record: AchievementGoalDetail) -> [AchievementGoalDetail] {
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
        // 한 할일은 주간 목표 하나에만 붙는다(`AchievementMemoLinkPolicy`).
        // 저장할 때 막는 것만으로는 **규칙 이전에 이미 두 목표에 묶인 데이터**가 정리되지 않아
        // 읽을 때도 같은 규칙으로 소유자를 가린다 — 저장된 값은 건드리지 않는다.
        // 소유자가 연결을 풀면 그 할일은 다시 자유로워진다.
        // **닫힌 목표는 소유권 다툼에서 빠진다.** 계속 쥐고 있으면 「이번 주에 다시」로 만든
        // 목표가 같은 할일을 되찾지 못한다. 닫힌 목표 자신은 저장된 연결을 그대로 보여 준다 —
        // 지나간 주의 기록이라 나중에 소유자가 바뀐다고 내용이 달라지면 안 된다.
        let memoOwners = AchievementMemoLinkPolicy.owners(in: records.filter { $0.closedAt == nil })

        /// 이 목표가 실제로 그려야 할 연결 목록.
        ///
        /// **삭제 상태는 목표가 아니라 할일이 갖는다.** 최근 삭제로 보낸 할일의 id 는 목표에
        /// 그대로 남아 있고(복구하면 다시 이어져야 하니까), 읽을 때마다 여기서 걸러낸다.
        /// 저장 시점에 목표를 고쳐 쓰면 복구할 길이 사라진다.
        func liveLinkedMemoIDs(for record: AchievementGoalDetail) -> [UUID] {
            let live = record.linkedMemoIDs.filter { memoByID[$0] != nil }
            // 월간·연간은 할일을 직접 묶지 않고 하위 목표에서 올려 받는다. 소유자 규칙은
            // 주간끼리만 따진다 — 여기에 걸면 상위 목표의 직접 연결이 통째로 사라진다.
            guard record.cadence == AchievementMemoLinkPolicy.linkableCadence else { return live }
            guard record.closedAt == nil else { return live }
            return live.filter { memoOwners[$0]?.id == record.id }
        }
        func directProgress(for record: AchievementGoalDetail) -> (done: Int, total: Int) {
            let linkedMemos = liveLinkedMemoIDs(for: record).compactMap { memoByID[$0] }
            guard !linkedMemos.isEmpty else { return (0, 0) }
            // 사라진 연결만큼 목표치도 줄인다. 안 줄이면 3개 중 1개를 지운 목표가
            // 남은 2개를 다 끝내도 2/3 에서 멈춰 영원히 달성되지 않는다.
            let missing = record.linkedMemoIDs.count - linkedMemos.count
            return (linkedMemos.filter(\.isCompleted).count, max(1, record.targetCount - missing))
        }
        func progress(for record: AchievementGoalDetail, visited: Set<UUID> = []) -> (done: Int, total: Int) {
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
        func descendantMemoIDs(for record: AchievementGoalDetail, visited: Set<UUID> = []) -> [UUID] {
            guard !visited.contains(record.id) else {
                return liveLinkedMemoIDs(for: record)
            }
            let nextVisited = visited.union([record.id])
            let childMemoIDs = childRecords(for: record).flatMap { descendantMemoIDs(for: $0, visited: nextVisited) }
            return Array(Set(liveLinkedMemoIDs(for: record) + childMemoIDs))
        }
        return records.map { record in
            let sourceMemoIDs = descendantMemoIDs(for: record)
            let linkedMemos = sourceMemoIDs.compactMap { memoByID[$0] }
                .sorted { memoDate($0) < memoDate($1) }
            let recordDate = linkedMemos
                .filter(\.isCompleted)
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
            // 달성 도장(`completedAt`)은 여기서 찍지 않는다. 예전에는 이 자리에서
            // 저장소에 직접 썼는데, **화면을 그리는 도중에 DB 가 바뀌는** 셈이었다.
            // 지금은 조립만 하고, 새로 달성된 목표를 골라 내는 일은
            // `newlyCompletedGoalIDs(...)` 가 맡는다.
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
                sourceMemoIDs: sourceMemoIDs,
                closedAt: record.closedAt,
                closedReason: record.closedReason
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

    static func timeline(for goal: AchievementGoal, memos: [AchievementMemoDetail], weekStarting weekStart: Date, referenceDate: Date = Date()) -> [AchievementTimelineItem] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: weekStart)
        let linked = memos.filter { goal.sourceMemoIDs.contains($0.id) }
        let completedCount = linked.filter(\.isCompleted).count
        let lastCompletedDate = linked.filter(\.isCompleted).compactMap(timelineDate).max()

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
            let isCompletedDay = dayMemos.contains(where: \.isCompleted)
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
                        isCompleted: memo.isCompleted,
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
        memos: [AchievementMemoDetail],
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
            // 같은 할일이 여러 목표에 묶여 있어도 카드는 하나다.
            // 한 할일은 주간 목표 하나에만 묶이는 게 규칙(`AchievementMemoLinkPolicy`)이지만,
            // 규칙 이전에 만들어진 데이터가 남아 있어 여기서도 한 번 더 접는다.
            var seenMemoIDs = Set<UUID>()
            let todos = sortedTodos(
                dayItems.flatMap { goal, item in
                    item.todos.compactMap { todo -> AchievementTimelineTodo? in
                        guard seenMemoIDs.insert(todo.memoID).inserted else { return nil }
                        return AchievementTimelineTodo(
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

    /// 이번에 처음 달성된 목표. 저장소에 달성 시각을 찍어 달라고 할 대상이다.
    ///
    /// **한 번 찍은 값은 되돌리지 않는다.** 달성이 풀리는 일(할일을 더 묶음)은 있어도
    /// «그때 달성했었다» 는 사실은 변하지 않는다 — 그래서 `completedAt == nil` 인 것만 고른다.
    static func newlyCompletedGoalIDs(
        goals: [AchievementGoal],
        details: [AchievementGoalDetail]
    ) -> [UUID] {
        let stamped = Set(details.filter { $0.completedAt != nil }.map(\.id))
        return goals.filter { $0.isComplete && !stamped.contains($0.id) }.map(\.id)
    }

    static func displayRule(for record: AchievementGoalDetail, total: Int) -> String {
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

    /// `AchievementMemoDetail.date` 와 같다. 호출부가 많아 이름을 남겨 둔다.
    static func memoDate(_ memo: AchievementMemoDetail) -> Date {
        memo.date
    }

    /// 카드가 어느 요일 칸에 놓일지, 칸 안에서 몇 번째로 놓일지를 함께 정하는 기준.
    /// 타임라인은 «언제 하는 일인지»를 읽는 화면이라 시작 시각을 먼저 본다.
    private static func timelineDate(_ memo: AchievementMemoDetail) -> Date? {
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

    static func dateRangeText(for memo: AchievementMemoDetail) -> String {
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

    static func todoMetaText(for memo: AchievementMemoDetail) -> String {
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

    static func todoDetail(for memo: AchievementMemoDetail, referenceDate: Date = Date()) -> String {
        if memo.isCompleted {
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

    static func todoStatus(for memo: AchievementMemoDetail, referenceDate: Date = Date()) -> AchievementTodoStatus {
        if memo.isCompleted {
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
