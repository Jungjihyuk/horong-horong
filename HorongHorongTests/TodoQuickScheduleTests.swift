import XCTest
@testable import 호롱호롱

/// 상세 화면의 날짜 빠른 선택이 «오늘이 무슨 요일이냐» 에 따라 어디로 가는지 못 박는다.
///
/// 요일을 기다리지 않고 검사하려고 `now` 를 주입한다 — 화요일에 «주말» 을 눌러 보려고
/// 화요일까지 기다릴 수는 없다.
final class TodoQuickScheduleTests: XCTestCase {

    /// 한국 기준(주 시작 = 일요일). 지역 설정에 흔들리지 않게 못 박는다.
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        return calendar
    }()

    /// 2026년 8월 30일은 일요일, 31일은 월요일, 9월 5일은 토요일이다.
    private func day(_ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = month
        components.day = day
        components.hour = 10
        return calendar.date(from: components)!
    }

    private func offset(_ option: TodoQuickSchedule, on date: Date) -> Int? {
        option.dayOffset(now: date, calendar: calendar)
    }

    // MARK: - 오늘 · 내일

    func testTodayAndTomorrowAreFixed() {
        for date in [day(8, 30), day(8, 31), day(9, 2), day(9, 5)] {
            XCTAssertEqual(offset(.today, on: date), 0)
            XCTAssertEqual(offset(.tomorrow, on: date), 1)
        }
    }

    // MARK: - 주말

    func testWeekendGoesToTheComingSaturday() {
        XCTAssertEqual(offset(.weekend, on: day(8, 31)), 5, "월요일 → 9/5 토요일")
        XCTAssertEqual(offset(.weekend, on: day(9, 2)), 3, "수요일 → 9/5 토요일")
        XCTAssertEqual(offset(.weekend, on: day(9, 4)), 1, "금요일 → 9/5 토요일")
    }

    /// 토요일에 눌렀는데 엿새 뒤로 밀리면 누른 사람의 뜻과 다르다.
    func testWeekendStaysOnTodayDuringTheWeekend() {
        XCTAssertEqual(offset(.weekend, on: day(9, 5)), 0, "토요일 → 오늘")
        XCTAssertEqual(offset(.weekend, on: day(8, 30)), 0, "일요일 → 오늘")
    }

    // MARK: - 다음 주

    func testNextWeekAlwaysLandsOnAMonday() {
        for date in [day(8, 30), day(8, 31), day(9, 2), day(9, 5)] {
            let offset = try! XCTUnwrap(offset(.nextWeek, on: date))
            let target = calendar.date(byAdding: .day, value: offset, to: date)!
            XCTAssertEqual(calendar.component(.weekday, from: target), 2, "월요일이어야 한다")
            XCTAssertGreaterThan(offset, 0, "지난 날로 가면 안 된다")
        }
    }

    func testNextWeekSkipsTheCurrentWeek() {
        // 8/30(일)은 이번 주의 첫날이다. 하루 뒤 월요일은 아직 이번 주라 건너뛰어야 한다.
        XCTAssertEqual(offset(.nextWeek, on: day(8, 30)), 8, "일요일 → 9/7 월요일")
        XCTAssertEqual(offset(.nextWeek, on: day(8, 31)), 7, "월요일 → 9/7 월요일")
        XCTAssertEqual(offset(.nextWeek, on: day(9, 5)), 2, "토요일 → 9/7 월요일")
    }

    // MARK: - 언젠가

    /// «언젠가» 만 갈 날짜가 없다. 화면은 이 `nil` 을 보고 날짜를 지운다.
    func testSomedayHasNoTarget() {
        XCTAssertNil(offset(.someday, on: day(8, 31)))
        for option in TodoQuickSchedule.allCases where option != .someday {
            XCTAssertNotNil(offset(option, on: day(8, 31)), "\(option.title) 은 갈 날짜가 있어야 한다")
        }
    }
}
