import Foundation

/// 팝오버 Todo 시간축 한 줄. 저장 모델 대신 화면에 필요한 값만 담는다.
struct TodoTimelineItem: Identifiable, Equatable, Sendable {
    enum State: Equatable, Sendable {
        case completed
        case elapsed(minutes: Int)
        case active(progress: Double)
        case upcoming(minutes: Int)
    }

    let todo: TodoItem
    let state: State

    var id: UUID { todo.id }
}

struct TodoTimeline: Equatable, Sendable {
    let scheduled: [TodoTimelineItem]
    let unscheduled: [TodoTimelineItem]
    /// 첫 미래 일정의 ID. 없으면 현재 시각은 모든 일정 뒤에 있다.
    let nextID: UUID?

    var isEmpty: Bool { scheduled.isEmpty && unscheduled.isEmpty }
}
