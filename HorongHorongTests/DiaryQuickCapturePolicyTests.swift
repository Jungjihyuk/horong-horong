import XCTest
@testable import 호롱호롱

final class DiaryQuickCapturePolicyTests: XCTestCase {
    private var calendar: Calendar = {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }()

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: hour, minute: minute))!
    }

    func testCueAppendsWithoutChangingExistingBody() {
        XCTAssertEqual(
            DiaryQuickCapturePolicy.appending(" 회의 #프로젝트 ", at: at(14, 32), to: "아침 기록", calendar: calendar),
            "아침 기록\n• 14:32 회의 #프로젝트"
        )
    }

    func testEmptyCueIsRejectedAndExistingNewlineIsReused() {
        XCTAssertNil(DiaryQuickCapturePolicy.appending("  ", at: at(9), to: "", calendar: calendar))
        XCTAssertEqual(
            DiaryQuickCapturePolicy.appending("산책", at: at(9, 5), to: "본문\n", calendar: calendar),
            "본문\n• 09:05 산책"
        )
    }

    func testNoonSwitchesFromMorningToAfternoon() {
        XCTAssertEqual(DiaryQuickCapturePolicy.slot(at: at(11, 59), calendar: calendar), .morning)
        XCTAssertEqual(DiaryQuickCapturePolicy.slot(at: at(12), calendar: calendar), .afternoon)
    }
}
