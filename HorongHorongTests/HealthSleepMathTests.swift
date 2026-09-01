import XCTest
@testable import 호롱호롱

final class HealthSleepMathTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var day: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
    }

    func testWindowIsPreviousEveningToSameDayEvening() {
        let window = HealthSleepMath.window(forDay: day, calendar: calendar)
        XCTAssertEqual(calendar.component(.hour, from: window.start), 18)
        XCTAssertEqual(calendar.component(.day, from: window.start), 31)
        XCTAssertEqual(calendar.component(.hour, from: window.end), 18)
        XCTAssertEqual(calendar.component(.day, from: window.end), 1)
    }

    func testMergesOverlappingAsleepSamplesAndIgnoresInBed() {
        let window = HealthSleepMath.window(forDay: day, calendar: calendar)
        let start = calendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 23))!
        let samples = [
            (start: start, end: start.addingTimeInterval(3600), value: 3),
            (start: start.addingTimeInterval(1800), end: start.addingTimeInterval(5400), value: 4),
            (start: start, end: start.addingTimeInterval(10_800), value: 0),
        ]
        XCTAssertEqual(HealthSleepMath.hours(from: samples, window: window), 1.5)
    }

    func testRoundsToHalfHour() {
        XCTAssertEqual(HealthSleepMath.roundedToHalfHour(7.24), 7.0)
        XCTAssertEqual(HealthSleepMath.roundedToHalfHour(7.26), 7.5)
    }

    func testEmptyAsleepSamplesYieldNil() {
        let window = HealthSleepMath.window(forDay: day, calendar: calendar)
        XCTAssertNil(HealthSleepMath.hours(from: [], window: window))
    }
}
