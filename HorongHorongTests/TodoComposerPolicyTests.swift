import XCTest
@testable import 호롱호롱

/// 빠른 입력 접두어(`[내일|모레] [n분|n시간] 제목`) 해석 규칙.
///
/// `now` 를 넣고 검사하므로 실행 시각과 무관하게 같은 결과가 나온다.
final class TodoComposerPolicyTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    /// 2026-09-05(토) 14:37. 오전 9시가 아닌 시각을 골라 접두어가 시각을 덮어쓰는지 본다.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 14, minute: 37))!
    }

    private func parse(_ text: String) -> TodoComposerPolicy.Entry {
        TodoComposerPolicy.parse(text, now: now, calendar: calendar)
    }

    private func parts(_ date: Date) -> DateComponents {
        calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    // MARK: - 날짜 접두어

    func testPlainTitleGoesToTodayNineAM() {
        let entry = parse("장보기")

        XCTAssertEqual(entry.title, "장보기")
        XCTAssertEqual(parts(entry.startDate), DateComponents(year: 2026, month: 9, day: 5, hour: 9, minute: 0))
        XCTAssertNil(entry.deadline)
    }

    func testTomorrowKeywordMovesStartToNextDay() {
        let entry = parse("내일 장보기")

        XCTAssertEqual(entry.title, "장보기")
        XCTAssertEqual(parts(entry.startDate), DateComponents(year: 2026, month: 9, day: 6, hour: 9, minute: 0))
        XCTAssertNil(entry.deadline)
    }

    func testDayAfterTomorrowKeywordMovesStartTwoDays() {
        let entry = parse("모레 발표 준비")

        XCTAssertEqual(entry.title, "발표 준비")
        XCTAssertEqual(parts(entry.startDate), DateComponents(year: 2026, month: 9, day: 7, hour: 9, minute: 0))
    }

    /// 월말에 «모레» 를 적으면 달을 넘어야 한다.
    func testDayKeywordCrossesMonthBoundary() {
        let lastDay = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 23, minute: 50))!
        let entry = TodoComposerPolicy.parse("모레 정산", now: lastDay, calendar: calendar)

        XCTAssertEqual(parts(entry.startDate), DateComponents(year: 2026, month: 10, day: 2, hour: 9, minute: 0))
    }

    // MARK: - 소요 시간 접두어

    func testMinutesOnlyKeepsTodayAndSetsDeadline() {
        let entry = parse("30분 산책")

        XCTAssertEqual(entry.title, "산책")
        XCTAssertEqual(parts(entry.startDate), DateComponents(year: 2026, month: 9, day: 5, hour: 9, minute: 0))
        XCTAssertEqual(parts(entry.deadline!), DateComponents(year: 2026, month: 9, day: 5, hour: 9, minute: 30))
    }

    func testHoursOnlyKeepsTodayAndSetsDeadline() {
        let entry = parse("2시간 코딩")

        XCTAssertEqual(entry.title, "코딩")
        XCTAssertEqual(parts(entry.deadline!), DateComponents(year: 2026, month: 9, day: 5, hour: 11, minute: 0))
    }

    func testDayKeywordAndDurationCombine() {
        let entry = parse("내일 90분 회의")

        XCTAssertEqual(entry.title, "회의")
        XCTAssertEqual(parts(entry.startDate), DateComponents(year: 2026, month: 9, day: 6, hour: 9, minute: 0))
        XCTAssertEqual(parts(entry.deadline!), DateComponents(year: 2026, month: 9, day: 6, hour: 10, minute: 30))
    }

    func testDurationBeforeDayKeywordIsNotADayKeyword() {
        // 순서를 지키지 않으면 접두어가 아니다 — 「30분」만 떼고 나머지는 제목으로 남는다.
        let entry = parse("30분 내일 회의")

        XCTAssertEqual(entry.title, "내일 회의")
        XCTAssertEqual(parts(entry.startDate), DateComponents(year: 2026, month: 9, day: 5, hour: 9, minute: 0))
        XCTAssertEqual(parts(entry.deadline!), DateComponents(year: 2026, month: 9, day: 5, hour: 9, minute: 30))
    }

    // MARK: - 접두어로 보지 않는 것들

    func testKeywordWithoutTrailingSpaceStaysInTitle() {
        let entry = parse("내일부터 장보기")

        XCTAssertEqual(entry.title, "내일부터 장보기")
        XCTAssertEqual(parts(entry.startDate), DateComponents(year: 2026, month: 9, day: 5, hour: 9, minute: 0))
    }

    func testKeywordAloneStaysAsTitle() {
        let entry = parse("내일")

        XCTAssertEqual(entry.title, "내일")
        XCTAssertEqual(parts(entry.startDate), DateComponents(year: 2026, month: 9, day: 5, hour: 9, minute: 0))
    }

    /// 「내일 30분」은 떼고 나면 제목이 없다. 날짜만 받고 「30분」은 제목으로 남긴다.
    func testDurationWithoutTitleStaysAsTitle() {
        let entry = parse("내일 30분")

        XCTAssertEqual(entry.title, "30분")
        XCTAssertEqual(parts(entry.startDate), DateComponents(year: 2026, month: 9, day: 6, hour: 9, minute: 0))
        XCTAssertNil(entry.deadline)
    }

    func testZeroDurationIsNotAPrefix() {
        let entry = parse("0분 낮잠")

        XCTAssertEqual(entry.title, "0분 낮잠")
        XCTAssertNil(entry.deadline)
    }

    func testUnknownUnitIsNotADuration() {
        let entry = parse("3일 여행")

        XCTAssertEqual(entry.title, "3일 여행")
        XCTAssertNil(entry.deadline)
    }

    /// 곱셈이 넘칠 만큼 큰 수는 소요 시간이 아니라 제목이다.
    func testOversizedDurationIsNotAPrefix() {
        let entry = parse("12345678시간 버티기")

        XCTAssertEqual(entry.title, "12345678시간 버티기")
        XCTAssertNil(entry.deadline)
    }

    func testExtraSpacesBetweenPrefixesAreIgnored() {
        let entry = parse("내일   2시간   집중")

        XCTAssertEqual(entry.title, "집중")
        XCTAssertEqual(parts(entry.startDate), DateComponents(year: 2026, month: 9, day: 6, hour: 9, minute: 0))
        XCTAssertEqual(parts(entry.deadline!), DateComponents(year: 2026, month: 9, day: 6, hour: 11, minute: 0))
    }

    // MARK: - 구체적 시간 범위 문법 (9시 30분 ~ 10시, 9시부터 9시 반까지 등)

    func testSpecificTimeRangeTilde() {
        let entry = parse("내일 9시 30분 ~ 10시 회의")

        XCTAssertEqual(entry.title, "회의")
        XCTAssertEqual(parts(entry.startDate), DateComponents(year: 2026, month: 9, day: 6, hour: 9, minute: 30))
        XCTAssertEqual(parts(entry.deadline!), DateComponents(year: 2026, month: 9, day: 6, hour: 10, minute: 0))
        XCTAssertTrue(entry.hasExplicitSchedule)
        XCTAssertEqual(entry.scheduleSummary, "내일 09:30 ~ 10:00")
    }

    func testSpecificTimeRangeColonFormat() {
        let entry = parse("내일 9:30~10:00 회의")

        XCTAssertEqual(entry.title, "회의")
        XCTAssertEqual(parts(entry.startDate), DateComponents(year: 2026, month: 9, day: 6, hour: 9, minute: 30))
        XCTAssertEqual(parts(entry.deadline!), DateComponents(year: 2026, month: 9, day: 6, hour: 10, minute: 0))
        XCTAssertEqual(entry.scheduleSummary, "내일 09:30 ~ 10:00")
    }

    func testSpecificTimeRangeHalfHourKeyword() {
        let entry = parse("내일 9시 반 ~ 10시 회의")

        XCTAssertEqual(entry.title, "회의")
        XCTAssertEqual(parts(entry.startDate), DateComponents(year: 2026, month: 9, day: 6, hour: 9, minute: 30))
        XCTAssertEqual(parts(entry.deadline!), DateComponents(year: 2026, month: 9, day: 6, hour: 10, minute: 0))
    }

    func testSpecificTimeRangeFromUntil() {
        let entry = parse("내일 9시부터 9시 반까지 회의")

        XCTAssertEqual(entry.title, "회의")
        XCTAssertEqual(parts(entry.startDate), DateComponents(year: 2026, month: 9, day: 6, hour: 9, minute: 0))
        XCTAssertEqual(parts(entry.deadline!), DateComponents(year: 2026, month: 9, day: 6, hour: 9, minute: 30))
        XCTAssertEqual(entry.scheduleSummary, "내일 09:00 ~ 09:30")
    }

    func testSpecificTimeStartAndDuration() {
        let entry = parse("내일 9시 시작 30분간 회의")

        XCTAssertEqual(entry.title, "회의")
        XCTAssertEqual(parts(entry.startDate), DateComponents(year: 2026, month: 9, day: 6, hour: 9, minute: 0))
        XCTAssertEqual(parts(entry.deadline!), DateComponents(year: 2026, month: 9, day: 6, hour: 9, minute: 30))
        XCTAssertEqual(entry.scheduleSummary, "내일 09:00 (30분)")
    }

    func testSpecificTimeStartAndDurationShort() {
        let entry = parse("내일 9시 30분간 회의")

        XCTAssertEqual(entry.title, "회의")
        XCTAssertEqual(parts(entry.startDate), DateComponents(year: 2026, month: 9, day: 6, hour: 9, minute: 0))
        XCTAssertEqual(parts(entry.deadline!), DateComponents(year: 2026, month: 9, day: 6, hour: 9, minute: 30))
    }

    func testSpecificTimeStartAndHourDuration() {
        let entry = parse("내일 오후 2시 1시간 미팅")

        XCTAssertEqual(entry.title, "미팅")
        XCTAssertEqual(parts(entry.startDate), DateComponents(year: 2026, month: 9, day: 6, hour: 14, minute: 0))
        XCTAssertEqual(parts(entry.deadline!), DateComponents(year: 2026, month: 9, day: 6, hour: 15, minute: 0))
        XCTAssertEqual(entry.scheduleSummary, "내일 14:00 (1시간)")
    }

    func testSpecificTimeOnly() {
        let entry = parse("내일 오후 3시 치과")

        XCTAssertEqual(entry.title, "치과")
        XCTAssertEqual(parts(entry.startDate), DateComponents(year: 2026, month: 9, day: 6, hour: 15, minute: 0))
        XCTAssertNil(entry.deadline)
        XCTAssertEqual(entry.scheduleSummary, "내일 15:00")
    }

    func testDayOfWeekKeyword() {
        // now는 2026-09-05 토요일. 일요일은 9월 6일.
        let entry = parse("일요일 10시 산책")

        XCTAssertEqual(entry.title, "산책")
        XCTAssertEqual(parts(entry.startDate), DateComponents(year: 2026, month: 9, day: 6, hour: 10, minute: 0))
        XCTAssertEqual(entry.scheduleSummary, "일요일 10:00")
    }

    func testScheduleSummaryForPlainTitleIsNil() {
        let entry = parse("장보기")
        XCTAssertFalse(entry.hasExplicitSchedule)
        XCTAssertNil(entry.scheduleSummary)
    }
}
