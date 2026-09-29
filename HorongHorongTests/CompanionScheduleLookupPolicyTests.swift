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
        CompanionMemoSummary(title: title, isCompleted: false, startDate: at(day, time), deadline: at(day, time))
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
        let loose = CompanionMemoSummary(title: "장보기", isCompleted: false, startDate: at("2026-09-18", "08:12"), deadline: nil)
        let items = CompanionScheduleLookupPolicy.entries(from: [loose], calendar: calendar)
        XCTAssertEqual(items.first?.date, "2026-09-18")
        XCTAssertEqual(items.first?.time, "")
        XCTAssertEqual(
            CompanionScheduleLookupPolicy.lookup(items, date: "2026-09-18", after: "07:00", nextOnly: false, now: now, calendar: calendar),
            []
        )
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
