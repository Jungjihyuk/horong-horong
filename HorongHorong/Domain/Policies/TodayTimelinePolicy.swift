import Foundation

/// 오늘 할 일을 읽기 쉬운 세로 시간축으로 만든다.
enum TodoTimelinePolicy {
    static func make(
        todos: [TodoItem],
        now: Date,
        calendar: Calendar = .current
    ) -> TodoTimeline {
        let today = todos.filter { item in
            !item.isRecentlyDeleted && item.bucket(now: now) == .today
        }
        let scheduledTodos = today.filter { $0.startDate != nil }.sorted(by: isEarlier)
        let unscheduledTodos = today.filter { $0.startDate == nil }.sorted { $0.createdAt < $1.createdAt }
        let scheduled = scheduledTodos.map { item($0, now: now) }
        let unscheduled = unscheduledTodos.map { item($0, now: now) }
        let nextID = scheduledTodos.first { ($0.startDate ?? .distantPast) > now }?.id
        return TodoTimeline(scheduled: scheduled, unscheduled: unscheduled, nextID: nextID)
    }

    private static func item(_ todo: TodoItem, now: Date) -> TodoTimelineItem {
        if todo.isCompleted { return TodoTimelineItem(todo: todo, state: .completed) }
        guard let start = todo.startDate else {
            return TodoTimelineItem(todo: todo, state: .upcoming(minutes: 0))
        }
        if let end = todo.deadline, end > start, now >= start, now < end {
            let progress = now.timeIntervalSince(start) / end.timeIntervalSince(start)
            return TodoTimelineItem(todo: todo, state: .active(progress: min(max(progress, 0), 1)))
        }
        if start > now {
            return TodoTimelineItem(todo: todo, state: .upcoming(minutes: roundedMinutes(start.timeIntervalSince(now))))
        }
        let reference = todo.deadline.map { max($0, start) } ?? start
        return TodoTimelineItem(todo: todo, state: .elapsed(minutes: roundedMinutes(now.timeIntervalSince(reference))))
    }

    private static func roundedMinutes(_ interval: TimeInterval) -> Int {
        max(0, Int(ceil(interval / 60)))
    }

    private static func isEarlier(_ lhs: TodoItem, _ rhs: TodoItem) -> Bool {
        let left = lhs.startDate ?? .distantFuture
        let right = rhs.startDate ?? .distantFuture
        if left != right { return left < right }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
