import XCTest
@testable import 호롱호롱

final class TodayTimelinePolicyTests: XCTestCase {
    private var calendar: Calendar = {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return value
    }()

    private func at(_ hour: Int, _ minute: Int = 0, day: Int = 7) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    private func todo(_ title: String, start: Date?, end: Date? = nil, done: Bool = false) -> TodoItem {
        TodoItem(
            id: UUID(), content: title, startDate: start, deadline: end,
            isCompleted: done, completionStateChangedAt: done ? at(10) : nil, deletedAt: nil,
            isLinkedToReminders: false, reminderCalendarIdentifier: nil,
            isPinned: false, createdAt: at(0), updatedAt: at(0)
        )
    }

    func testTodayTodosAreSortedAndOtherDaysAreExcluded() {
        let timeline = TodoTimelinePolicy.make(
            todos: [todo("늦게", start: at(16)), todo("내일", start: at(9, day: 8)), todo("일찍", start: at(9))],
            now: at(12), calendar: calendar
        )
        XCTAssertEqual(timeline.scheduled.map(\.todo.displayTitle), ["일찍", "늦게"])
        XCTAssertEqual(timeline.nextID, timeline.scheduled.last?.id)
    }

    func testActiveRangeReportsClampedProgress() {
        let timeline = TodoTimelinePolicy.make(
            todos: [todo("작업", start: at(10), end: at(12))], now: at(11), calendar: calendar
        )
        XCTAssertEqual(timeline.scheduled.first?.state, .active(progress: 0.5))
    }

    func testUpcomingElapsedAndCompletedStates() {
        let timeline = TodoTimelinePolicy.make(
            todos: [
                todo("지남", start: at(9)),
                todo("다음", start: at(13)),
                todo("완료", start: at(10), done: true),
            ], now: at(12), calendar: calendar
        )
        XCTAssertEqual(timeline.scheduled[0].state, .elapsed(minutes: 180))
        XCTAssertEqual(timeline.scheduled[1].state, .completed)
        XCTAssertEqual(timeline.scheduled[2].state, .upcoming(minutes: 60))
    }

    func testEmptyInputProducesEmptyTimeline() {
        XCTAssertTrue(TodoTimelinePolicy.make(todos: [], now: at(12), calendar: calendar).isEmpty)
    }
}
