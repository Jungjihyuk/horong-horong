import XCTest
@testable import 호롱호롱

final class MemoClassifierTests: XCTestCase {
    func testURLOnFirstLineBecomesReference() {
        XCTAssertEqual(
            MemoClassifier.classify(
                content: "https://example.com/path\n읽을거리",
                startDate: nil,
                deadline: nil
            ),
            .reference
        )
    }

    func testBareWWWBecomesReference() {
        XCTAssertEqual(
            MemoClassifier.classify(content: "www.example.com", startDate: nil, deadline: nil),
            .reference
        )
    }

    func testURLWinsOverDates() {
        let now = Date()
        XCTAssertEqual(
            MemoClassifier.classify(
                content: "https://example.com",
                startDate: now,
                deadline: now
            ),
            .reference
        )
    }

    func testDatedMemoBecomesTodo() {
        XCTAssertEqual(
            MemoClassifier.classify(content: "헬스장 가기", startDate: Date(), deadline: nil),
            .todo
        )
        XCTAssertEqual(
            MemoClassifier.classify(content: "책 반납", startDate: nil, deadline: Date()),
            .todo
        )
    }

    func testPlainMemoBecomesQuickNote() {
        XCTAssertEqual(
            MemoClassifier.classify(content: "떠오른 생각", startDate: nil, deadline: nil),
            .quickNote
        )
    }

    func testPlainTextIsNotURL() {
        XCTAssertFalse(MemoClassifier.looksLikeURL("http라는 단어를 적은 메모"))
        XCTAssertFalse(MemoClassifier.looksLikeURL("ftp://example.com"))
    }
}

final class MemoRecentlyDeletedTests: XCTestCase {
    func testDeletedAtMarksRecentlyDeletedWithoutChangingBucket() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 12))!
        let memo = Memo(content: "치과", section: .todo)
        memo.startDate = now
        XCTAssertFalse(memo.isRecentlyDeleted)
        XCTAssertEqual(
            TodoBucket.of(
                startDate: memo.startDate,
                deadline: memo.deadline,
                isCompleted: false,
                now: now,
                calendar: calendar
            ),
            .today
        )

        memo.deletedAt = now
        XCTAssertTrue(memo.isRecentlyDeleted)
        XCTAssertEqual(
            TodoBucket.of(
                startDate: memo.startDate,
                deadline: memo.deadline,
                isCompleted: false,
                now: now,
                calendar: calendar
            ),
            .today
        )
    }

    func testTodayPlanningIgnoresRecentlyDeleted() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 12))!
        let memo = Memo(content: "지운 오늘 할 일", section: .todo)
        memo.startDate = now
        memo.deletedAt = now
        XCTAssertFalse(
            TodayPlanningReminderPolicy.isTodayTask(memo, now: now, calendar: calendar)
        )
    }
}

final class TodoBucketTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 12))!
    }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
    }

    func testDeadlinePreferredOverStart() {
        XCTAssertEqual(
            TodoBucket.of(startDate: day(-3), deadline: day(0), isCompleted: false, now: now, calendar: calendar),
            .today
        )
        XCTAssertEqual(
            TodoBucket.of(startDate: day(0), deadline: day(2), isCompleted: false, now: now, calendar: calendar),
            .upcoming
        )
    }

    func testStartUsedWhenDeadlineMissing() {
        XCTAssertEqual(
            TodoBucket.of(startDate: day(-1), deadline: nil, isCompleted: false, now: now, calendar: calendar),
            .overdue
        )
    }

    func testNoDateIsSomeday() {
        XCTAssertEqual(
            TodoBucket.of(startDate: nil, deadline: nil, isCompleted: false, now: now, calendar: calendar),
            .someday
        )
    }

    func testCompletedOverridesDates() {
        XCTAssertEqual(
            TodoBucket.of(startDate: day(-2), deadline: day(-1), isCompleted: true, now: now, calendar: calendar),
            .completed
        )
    }

    func testPlacementMovesTodayAndClearsSomeday() {
        let placed = TodoBucket.placement(
            into: .today,
            startDate: nil,
            deadline: nil,
            isCompleted: false,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(TodoBucket.of(startDate: placed.startDate, deadline: placed.deadline, isCompleted: placed.isCompleted, now: now, calendar: calendar), .today)

        let someday = TodoBucket.placement(
            into: .someday,
            startDate: day(0),
            deadline: nil,
            isCompleted: false,
            now: now,
            calendar: calendar
        )
        XCTAssertNil(someday.startDate)
        XCTAssertNil(someday.deadline)
        XCTAssertFalse(someday.isCompleted)
    }

    func testPlacementKeepsExistingUpcomingDate() {
        let future = day(4)
        let placed = TodoBucket.placement(
            into: .upcoming,
            startDate: future,
            deadline: nil,
            isCompleted: false,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(placed.startDate, future)
    }

    func testPlacementCompletesWithoutClearingDates() {
        let placed = TodoBucket.placement(
            into: .completed,
            startDate: day(0),
            deadline: nil,
            isCompleted: false,
            now: now,
            calendar: calendar
        )
        XCTAssertTrue(placed.isCompleted)
        XCTAssertEqual(placed.startDate, day(0))
    }

    func testPlacementUncompletesIntoOverdue() {
        let placed = TodoBucket.placement(
            into: .overdue,
            startDate: day(0),
            deadline: nil,
            isCompleted: true,
            now: now,
            calendar: calendar
        )
        XCTAssertFalse(placed.isCompleted)
        XCTAssertEqual(
            TodoBucket.of(startDate: placed.startDate, deadline: placed.deadline, isCompleted: placed.isCompleted, now: now, calendar: calendar),
            .overdue
        )
    }

}

final class TodoDueChipTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 12))!
    }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
    }

    func testOverdueTodayTomorrowAndLater() {
        XCTAssertEqual(TodoDueChip.of(startDate: day(-1), deadline: nil, now: now, calendar: calendar)?.label, "1일 지남")
        XCTAssertEqual(TodoDueChip.of(startDate: day(0), deadline: nil, now: now, calendar: calendar)?.label, "오늘")
        XCTAssertEqual(TodoDueChip.of(startDate: day(1), deadline: nil, now: now, calendar: calendar)?.label, "내일")
        XCTAssertEqual(TodoDueChip.of(startDate: day(2), deadline: nil, now: now, calendar: calendar)?.label, "2일 뒤")
        XCTAssertEqual(TodoDueChip.of(startDate: day(10), deadline: nil, now: now, calendar: calendar)?.label, "9월 11일")
        XCTAssertNil(TodoDueChip.of(startDate: nil, deadline: nil, now: now, calendar: calendar))
    }
}
