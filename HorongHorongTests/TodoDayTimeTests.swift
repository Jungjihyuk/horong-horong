import XCTest
@testable import 호롱호롱

/// 시각 다루기와 프리셋을 못 박는다.
final class TodoDayTimeTests: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        return calendar
    }()

    private func at(_ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 31
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    // MARK: - 시각 갈아 끼우기

    func testApplyingKeepsTheDay() {
        let changed = TodoDayTime.applying(hour: 15, minute: 30, to: at(8, 0), calendar: calendar)
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: changed)
        XCTAssertEqual(parts.day, 31)
        XCTAssertEqual(parts.month, 8)
        XCTAssertEqual(parts.hour, 15)
        XCTAssertEqual(parts.minute, 30)
    }

    // MARK: - 시각 프리셋

    func testPresetsCoverTheDayInOrder() {
        let hours = TodoTimePreset.allCases.map(\.hour)
        XCTAssertEqual(hours, [8, 10, 12, 15, 18, 21])
        XCTAssertEqual(hours, hours.sorted(), "아침부터 밤까지 순서대로 놓여야 한다")
    }

    /// 오후 시각도 «15시» 가 아니라 «3시» 로 읽어야 눈에 익는다.
    func testPresetLabelsUseTwelveHourWording() {
        XCTAssertEqual(TodoTimePreset.morning.valueLabel, "8시")
        XCTAssertEqual(TodoTimePreset.lunch.valueLabel, "12:30")
        XCTAssertEqual(TodoTimePreset.afternoon.valueLabel, "3시")
        XCTAssertEqual(TodoTimePreset.night.valueLabel, "9시")
    }
}
