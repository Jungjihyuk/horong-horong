import XCTest
import AppKit
@testable import 호롱호롱

/// 상세 화면이 날짜를 사람 말로 옮기는 규칙을 못 박는다.
///
/// 배지는 **저장하지 않는 파생 값**이다. 같은 날짜라도 자정이 지나면 «오늘» 이 «어제» 가 되어야
/// 하므로 `now` 를 주입해 자정 경계를 자정까지 기다리지 않고 검사한다.
final class TodoScheduleTextTests: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        return calendar
    }()

    private func day(_ month: Int, _ day: Int, year: Int = 2026, hour: Int = 10) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return calendar.date(from: components)!
    }

    private func badge(_ date: Date, now: Date) -> String? {
        TodoScheduleText.relativeBadge(date, now: now, calendar: calendar)
    }

    // MARK: - 배지

    func testNearbyDaysGetABadge() {
        let now = day(8, 31)
        XCTAssertEqual(badge(day(8, 31), now: now), "오늘")
        XCTAssertEqual(badge(day(9, 1), now: now), "내일")
        XCTAssertEqual(badge(day(9, 2), now: now), "모레")
        XCTAssertEqual(badge(day(8, 30), now: now), "어제")
    }

    func testFarFutureGetsNoBadge() {
        XCTAssertNil(badge(day(9, 20), now: day(8, 31)))
    }

    func testOverdueDaysAreCounted() {
        XCTAssertEqual(badge(day(8, 25), now: day(8, 31)), "6일 지남")
    }

    /// 시각이 아니라 **날짜**로 센다. 같은 날 밤 11시와 새벽 1시는 둘 다 «오늘» 이다.
    func testBadgeIgnoresTimeOfDay() {
        let now = day(8, 31, hour: 23)
        XCTAssertEqual(badge(day(8, 31, hour: 1), now: now), "오늘")
        XCTAssertEqual(badge(day(9, 1, hour: 0), now: now), "내일")
    }

    // MARK: - 큰 날짜 줄

    func testSameYearOmitsTheYear() {
        let text = TodoScheduleText.fullDay(day(8, 31), now: day(8, 1), calendar: calendar)
        XCTAssertTrue(text.contains("8"))
        XCTAssertTrue(text.contains("31"))
        XCTAssertFalse(text.contains("2026"), "같은 해에는 연도를 빼서 짧게 읽힌다")
    }

    func testDifferentYearShowsTheYear() {
        let text = TodoScheduleText.fullDay(day(1, 3, year: 2027), now: day(8, 31), calendar: calendar)
        XCTAssertTrue(text.contains("2027"), "해가 다르면 연도를 붙여야 헷갈리지 않는다")
    }

    // MARK: - 좁은 칸용 짧은 날짜

    /// 칸이 좁아도 «무슨 날인지» 는 남아야 한다. 요일만 줄이고 월·일은 지킨다.
    func testShortDayKeepsMonthAndDay() {
        let short = TodoScheduleText.shortDay(day(9, 10), now: day(9, 7), calendar: calendar)
        XCTAssertTrue(short.contains("9"))
        XCTAssertTrue(short.contains("10"))
    }

    /// **글자 «수» 로 재면 안 된다.** 한국어는 «목요일» → «(목)» 이라 개수가 같다.
    /// 좁은 칸에 들어가는지는 그려지는 폭으로만 판정할 수 있다.
    func testShortDayIsNarrowerThanFullDay() {
        let full = TodoScheduleText.fullDay(day(9, 10), now: day(9, 7), calendar: calendar)
        let short = TodoScheduleText.shortDay(day(9, 10), now: day(9, 7), calendar: calendar)
        XCTAssertNotEqual(short, full)
        let font = NSFont.systemFont(ofSize: 15.5, weight: .heavy)
        let width: (String) -> CGFloat = { ($0 as NSString).size(withAttributes: [.font: font]).width }
        XCTAssertLessThan(width(short), width(full), "짧은 쪽이 더 넓으면 좁은 칸에서 쓸 이유가 없다")
    }

    func testShortDayFollowsTheSameYearRule() {
        let sameYear = TodoScheduleText.shortDay(day(8, 31), now: day(8, 1), calendar: calendar)
        XCTAssertFalse(sameYear.contains("2026"))
        let otherYear = TodoScheduleText.shortDay(day(1, 3, year: 2027), now: day(8, 31), calendar: calendar)
        XCTAssertTrue(otherYear.contains("2027"), "해가 다르면 짧은 표현에서도 연도를 지킨다")
    }

    // MARK: - 미리알림 안내 문구

    func testDestinationMentionsListAndDate() {
        let text = TodoScheduleText.reminderDestination(
            listTitle: "업무",
            date: day(8, 31),
            now: day(8, 31),
            calendar: calendar
        )
        XCTAssertTrue(text.contains("업무"))
        XCTAssertTrue(text.contains("31"))
        XCTAssertTrue(text.hasSuffix("올라갑니다"))
    }

    func testDestinationWithoutDateSaysSo() {
        let text = TodoScheduleText.reminderDestination(
            listTitle: "기록",
            date: nil,
            now: day(8, 31),
            calendar: calendar
        )
        XCTAssertTrue(text.contains("기록"))
        XCTAssertTrue(text.contains("날짜 없이"))
    }

    // MARK: - 7일 띠

    func testStripNamesFirstTwoDaysByRelation() {
        XCTAssertEqual(TodoScheduleText.stripDayName(offset: 0, date: day(8, 31), calendar: calendar), "오늘")
        XCTAssertEqual(TodoScheduleText.stripDayName(offset: 1, date: day(9, 1), calendar: calendar), "내일")
    }

    func testStripNamesLaterDaysByWeekday() {
        let name = TodoScheduleText.stripDayName(offset: 2, date: day(9, 2), calendar: calendar)
        XCTAssertEqual(name, calendar.shortWeekdaySymbols[3], "9/2 는 수요일")
        XCTAssertNotEqual(name, "오늘")
    }
}
