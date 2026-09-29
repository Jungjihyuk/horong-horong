import XCTest
@testable import 호롱호롱

/// 평가기 가짜 저장소(`Evals/companion_eval.py` `SEED`, `FakeTools`)와 같은 입력·기대값으로 본다.
final class CompanionScheduleLookupPolicyTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }()

    /// 평가 기준 시각 2026-09-18 10:00 (Asia/Seoul)
    private var now: Date { at("2026-09-18", "10:00") }

    private func at(_ day: String, _ time: String) -> Date {
        CompanionScheduleLookupPolicy.saveDates(date: day, after: time, calendar: calendar)!.startDate
    }

    private func memo(_ title: String, _ day: String, _ time: String) -> CompanionMemoSummary {
        CompanionMemoSummary(id: UUID(), title: title, isCompleted: false, startDate: at(day, time), deadline: at(day, time))
    }

    private var entries: [CompanionScheduleLookupPolicy.Entry] {
        CompanionScheduleLookupPolicy.entries(from: [
            memo("팀 회의", "2026-09-18", "09:00"),
            memo("배포 점검", "2026-09-18", "15:00"),
            memo("면접 준비", "2026-09-19", "11:00"),
            memo("이력서 첨삭", "2026-09-25", "14:00"),
            memo("독서 모임", "2026-09-19", "17:00"),
        ], calendar: calendar)
    }

    private func titles(date: String = "", after: String = "", nextOnly: Bool = false) -> [String] {
        CompanionScheduleLookupPolicy
            .lookup(entries, date: date, after: after, nextOnly: nextOnly, now: now, calendar: calendar)
            .map(\.memo.title)
    }

    /// 이미 지난 오늘 오전 일정도 빼지 않는다.
    func testTodayReturnsAllItemsOfTheDay() {
        XCTAssertEqual(titles(date: "2026-09-18"), ["팀 회의", "배포 점검"])
    }

    func testTomorrowReturnsEveryItemInTimeOrder() {
        XCTAssertEqual(titles(date: "2026-09-19"), ["면접 준비", "독서 모임"])
    }

    func testAfterFiltersByTime() {
        XCTAssertEqual(titles(date: "2026-09-18", after: "14:00"), ["배포 점검"])
    }

    func testNextOnlyReturnsFirstItemAfterNow() {
        XCTAssertEqual(titles(nextOnly: true), ["배포 점검"])
    }

    func testEmptyDayReturnsNothing() {
        XCTAssertEqual(titles(date: "2026-09-20"), [])
    }

    /// 마감이 없는 할 일은 담은 날짜만 쓰고 시각은 비운다. 시간 조건에는 걸리지 않는다.
    func testUndatedTimeUsesStartDayWithoutClock() {
        let loose = CompanionMemoSummary(id: UUID(), title: "장보기", isCompleted: false, startDate: at("2026-09-18", "08:12"), deadline: nil)
        let items = CompanionScheduleLookupPolicy.entries(from: [loose], calendar: calendar)
        XCTAssertEqual(items.first?.date, "2026-09-18")
        XCTAssertEqual(items.first?.time, "")
        XCTAssertEqual(
            CompanionScheduleLookupPolicy.lookup(items, date: "2026-09-18", after: "07:00", nextOnly: false, now: now, calendar: calendar),
            []
        )
    }

    // MARK: - v5

    func testRangeLookupReturnsEveryItemInRange() {
        let found = CompanionScheduleLookupPolicy
            .lookup(entries, date: "2026-09-19", until: "2026-09-25", after: "", nextOnly: false, now: now, calendar: calendar)
            .map(\.memo.title)
        XCTAssertEqual(found, ["면접 준비", "독서 모임", "이력서 첨삭"])
    }

    func testMoveTargetsMatchByTitleKeyword() {
        XCTAssertEqual(CompanionScheduleLookupPolicy.moveTargets(entries, title: "면접").map(\.memo.title), ["면접 준비"])
        XCTAssertEqual(CompanionScheduleLookupPolicy.moveTargets(entries, title: "없는 일"), [])
        XCTAssertEqual(CompanionScheduleLookupPolicy.moveTargets(entries, title: "  "), [])
    }

    /// 새 시각을 말하지 않으면 원래 시각을 지킨다 (평가기 `schedule_move` 와 같다).
    func testMoveKeepsOriginalTimeUnlessNewTimeGiven() throws {
        let target = try XCTUnwrap(CompanionScheduleLookupPolicy.moveTargets(entries, title: "면접 준비").first)
        let kept = try XCTUnwrap(CompanionScheduleLookupPolicy.movedDates(target, date: "2026-09-21", after: "", calendar: calendar))
        XCTAssertEqual(CompanionScheduleLookupPolicy.day(try XCTUnwrap(kept.startDate), calendar), "2026-09-21")
        XCTAssertEqual(CompanionScheduleLookupPolicy.clock(try XCTUnwrap(kept.deadline), calendar), "11:00")
        let changed = try XCTUnwrap(CompanionScheduleLookupPolicy.movedDates(target, date: "2026-09-21", after: "16:30", calendar: calendar))
        XCTAssertEqual(CompanionScheduleLookupPolicy.clock(try XCTUnwrap(changed.startDate), calendar), "16:30")
    }

    /// 10시~11시 할 일은 옮겨도 한 시간짜리로 남는다.
    func testMoveKeepsDurationAndDayOnlyTodoStaysDayOnly() throws {
        let ranged = CompanionMemoSummary(id: UUID(), title: "회의", isCompleted: false,
                                          startDate: at("2026-09-19", "10:00"), deadline: at("2026-09-19", "11:00"))
        let entry = try XCTUnwrap(CompanionScheduleLookupPolicy.entries(from: [ranged], calendar: calendar).first)
        let kept = try XCTUnwrap(CompanionScheduleLookupPolicy.movedDates(entry, date: "2026-09-22", after: "", calendar: calendar))
        XCTAssertEqual(kept.startDate, at("2026-09-22", "10:00"))
        XCTAssertEqual(kept.deadline, at("2026-09-22", "11:00"))
        let shifted = try XCTUnwrap(CompanionScheduleLookupPolicy.movedDates(entry, date: "2026-09-22", after: "14:00", calendar: calendar))
        XCTAssertEqual(shifted.deadline, at("2026-09-22", "15:00"))

        let dayOnly = CompanionMemoSummary(id: UUID(), title: "장보기", isCompleted: false,
                                           startDate: calendar.startOfDay(for: at("2026-09-19", "00:00")), deadline: nil)
        let loose = try XCTUnwrap(CompanionScheduleLookupPolicy.entries(from: [dayOnly], calendar: calendar).first)
        let moved = try XCTUnwrap(CompanionScheduleLookupPolicy.movedDates(loose, date: "2026-09-22", after: "", calendar: calendar))
        XCTAssertEqual(moved.startDate, calendar.startOfDay(for: at("2026-09-22", "00:00")))
        XCTAssertNil(moved.deadline)
    }

    /// "10월 2일"이 2024년으로 나온 실제 사고(2026-09-29)를 저장 전에 잡는다.
    func testDateGuardCatchesPastWritesAndWeekdayMismatch() {
        let issue = { (date: String, isWrite: Bool, message: String) in
            CompanionScheduleLookupPolicy.dateIssue(date: date, isWrite: isWrite, message: message, now: self.now, calendar: self.calendar)
        }
        XCTAssertEqual(issue("2024-10-02", true, "10월 2일에 치과 추가해줘"), .past(date: "2024-10-02"))
        XCTAssertNil(issue("2024-10-02", false, "2024년 10월 2일 일정 보여줘"))
        XCTAssertEqual(
            issue("2026-10-01", true, "10월 1일 금요일에 치과 추가해줘"),
            .weekdayMismatch(date: "2026-10-01", said: "금요일", actual: "목요일")
        )
        XCTAssertNil(issue("2026-10-02", true, "10월 2일 금요일에 치과 추가해줘"))
        XCTAssertNil(issue("2026-09-21", true, "월요일 회의를 수요일로 옮겨줘"))
        XCTAssertNil(issue("2026-09-18", true, "오늘 할일에 우유 사기 추가해줘"))
    }

    func testSaveDatesFollowChatScheduleRule() {
        let timed = CompanionScheduleLookupPolicy.saveDates(date: "2026-09-19", after: "15:30", calendar: calendar)
        XCTAssertEqual(timed?.startDate, timed?.deadline)
        XCTAssertEqual(CompanionScheduleLookupPolicy.clock(timed!.startDate, calendar), "15:30")

        let dayOnly = CompanionScheduleLookupPolicy.saveDates(date: "2026-09-19", after: "", calendar: calendar)
        XCTAssertNil(dayOnly?.deadline)
        XCTAssertEqual(dayOnly?.startDate, calendar.startOfDay(for: timed!.startDate))
    }
}
