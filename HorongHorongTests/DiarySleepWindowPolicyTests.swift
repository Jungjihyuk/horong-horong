import XCTest
@testable import 호롱호롱

/// 수면 타임라인의 축 계산을 시계 없이 검사한다.
///
/// 정책이 `Date()` 를 직접 읽었다면 이 검사는 «자정 직전에 돌리면 깨지는» 테스트가 됐을 것이다.
final class DiarySleepWindowPolicyTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        return calendar
    }()

    /// 2026-09-06 00:00 KST
    private var day: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 6)) ?? Date()
    }

    private func time(_ month: Int, _ dayOfMonth: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: dayOfMonth, hour: hour, minute: minute)) ?? Date()
    }

    private let axis = DiarySleepAxis.default

    // MARK: - 축

    func testDefaultAxisRunsFromNineAtNightToNoon() {
        XCTAssertEqual(axis.startHour, 21)
        XCTAssertEqual(axis.endHour, 12)
        XCTAssertEqual(axis.hours, 15, accuracy: 0.0001)
        XCTAssertEqual(axis.tickInterval, 1, "기본 눈금은 1시간마다")
        XCTAssertEqual(axis.start(of: day, calendar: calendar), time(9, 5, 21))
        XCTAssertEqual(axis.end(of: day, calendar: calendar), time(9, 6, 12))
    }

    /// 시작이 끝보다 이르면 같은 날 안의 구간이다 — 전날로 넘기지 않는다.
    func testAxisWithinASingleDayDoesNotRollBack() {
        let sameDay = DiarySleepAxis(startHour: 1, endHour: 11, tickInterval: 2)

        XCTAssertEqual(sameDay.hours, 10, accuracy: 0.0001)
        XCTAssertEqual(sameDay.start(of: day, calendar: calendar), time(9, 6, 1))
        XCTAssertEqual(sameDay.end(of: day, calendar: calendar), time(9, 6, 11))
    }

    /// 시작과 끝이 같으면 0시간이 아니라 하루 전체다 — 그릴 수 없는 축을 만들지 않는다.
    func testAxisWithEqualBoundsSpansAFullDay() {
        XCTAssertEqual(DiarySleepAxis(startHour: 20, endHour: 20, tickInterval: 3).hours, 24, accuracy: 0.0001)
    }

    /// 범위를 벗어난 값은 저장소에 남아 있어도 축을 망가뜨리지 않는다.
    func testAxisNormalizesOutOfRangeInput() {
        let wrapped = DiarySleepAxis(startHour: 26, endHour: -2, tickInterval: 0)

        XCTAssertEqual(wrapped.startHour, 2)
        XCTAssertEqual(wrapped.endHour, 22)
        XCTAssertEqual(wrapped.tickInterval, 1, "간격은 최소 1시간")
    }

    func testTickIntervalNeverExceedsTheAxisLength() {
        XCTAssertEqual(DiarySleepAxis(startHour: 22, endHour: 2, tickInterval: 6).tickInterval, 4)
    }

    func testFractionAndDateAreInverses() {
        let midnight = time(9, 6, 0)
        let fraction = DiarySleepWindowPolicy.fraction(of: midnight, day: day, axis: axis, calendar: calendar)

        XCTAssertEqual(fraction, 3.0 / 15.0, accuracy: 0.0001)
        XCTAssertEqual(
            DiarySleepWindowPolicy.date(atFraction: fraction, day: day, axis: axis, calendar: calendar),
            midnight
        )
    }

    /// 축 밖은 양 끝으로 자른다. 그러지 않으면 막대가 차트 밖으로 나가 사라진다.
    func testFractionClampsOutsideTheAxis() {
        XCTAssertEqual(DiarySleepWindowPolicy.fraction(of: time(9, 5, 12), day: day, axis: axis, calendar: calendar), 0)
        XCTAssertEqual(DiarySleepWindowPolicy.fraction(of: time(9, 6, 20), day: day, axis: axis, calendar: calendar), 1)
    }

    func testDateSnapsToFiveMinutes() {
        // 축 시작(21시)에서 4시간 3분 뒤 = 01:03 → 01:05 로 붙는다.
        let fraction = (4 * 60 + 3) / (axis.hours * 60)
        let snapped = DiarySleepWindowPolicy.date(atFraction: fraction, day: day, axis: axis, calendar: calendar)

        XCTAssertEqual(calendar.component(.minute, from: snapped) % DiarySleepWindowPolicy.snapMinutes, 0)
        XCTAssertEqual(snapped, time(9, 6, 1, 5))
    }

    /// 기본 축은 1시간마다 눈금을 세운다 — 21, 22, … 12 로 16개.
    func testTicksFollowTheConfiguredInterval() {
        XCTAssertEqual(axis.ticks.map(\.hour), [21, 22, 23, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])
        XCTAssertEqual(axis.ticks.first?.fraction, 0)
        XCTAssertEqual(axis.ticks.last?.fraction, 1)
    }

    func testTicksHonourAWiderInterval() {
        let coarse = DiarySleepAxis(startHour: 21, endHour: 12, tickInterval: 3)

        XCTAssertEqual(coarse.ticks.map(\.hour), [21, 0, 3, 6, 9, 12])
    }

    /// 축 길이가 간격으로 나누어떨어지지 않아도 마지막 눈금은 축 끝에 붙는다.
    func testLastTickAlwaysLandsOnTheAxisEnd() {
        let uneven = DiarySleepAxis(startHour: 21, endHour: 12, tickInterval: 4)

        XCTAssertEqual(uneven.ticks.map(\.hour), [21, 1, 5, 9, 12])
        XCTAssertEqual(uneven.ticks.last?.fraction, 1)
    }

    /// 좁은 화면에서는 설정을 무시하는 대신 읽을 수 있는 만큼만 남긴다.
    func testThinnedTicksStayWithinTheRequestedCount() {
        let thinned = axis.ticks(maximumCount: 6)

        XCTAssertLessThanOrEqual(thinned.count, 7, "마지막 눈금 한 개는 항상 덧붙는다")
        XCTAssertEqual(thinned.first?.hour, 21)
        XCTAssertEqual(thinned.last?.fraction, 1)
    }

    func testThinningLeavesShortAxesAlone() {
        let coarse = DiarySleepAxis(startHour: 21, endHour: 12, tickInterval: 6)

        XCTAssertEqual(coarse.ticks(maximumCount: 6).count, coarse.ticks.count)
    }

    func testHourAtFractionWrapsPastMidnight() {
        XCTAssertEqual(axis.hour(atFraction: 0), 21)
        XCTAssertEqual(axis.hour(atFraction: 3.0 / 15.0), 0)
        XCTAssertEqual(axis.hour(atFraction: 1), 12)
    }

    // MARK: - 구간

    func testNormalizeRollsWakeTimePastMidnight() {
        let bed = time(9, 5, 23)
        let wake = time(9, 5, 7)

        let window = DiarySleepWindowPolicy.normalize(start: bed, end: wake)

        XCTAssertEqual(window.end, time(9, 6, 7))
        XCTAssertEqual(window.hours, 8, accuracy: 0.0001)
    }

    func testNormalizeLeavesAnOrderedWindowAlone() {
        let bed = time(9, 5, 23)
        let wake = time(9, 6, 6, 30)

        let window = DiarySleepWindowPolicy.normalize(start: bed, end: wake)

        XCTAssertEqual(window, DiarySleepWindow(start: bed, end: wake))
        XCTAssertEqual(window.hours, 7.5, accuracy: 0.0001)
    }

    /// 길이만 남은 옛 기록도 축 위에 자리를 얻는다 — 기상 7시 기준 역산.
    func testLegacyHoursLandOnTheAxis() {
        let window = DiarySleepWindowPolicy.window(hours: 8, day: day, calendar: calendar)

        XCTAssertEqual(window.end, time(9, 6, 7))
        XCTAssertEqual(window.start, time(9, 5, 23))
        XCTAssertGreaterThan(DiarySleepWindowPolicy.fraction(of: window.start, day: day, axis: axis, calendar: calendar), 0)
        XCTAssertLessThan(DiarySleepWindowPolicy.fraction(of: window.end, day: day, axis: axis, calendar: calendar), 1)
    }

    func testDefaultWindowIsElevenToSeven() {
        let window = DiarySleepWindowPolicy.defaultWindow(for: day, axis: axis, calendar: calendar)

        XCTAssertEqual(window.start, time(9, 5, 23))
        XCTAssertEqual(window.end, time(9, 6, 7))
        XCTAssertEqual(window.hours, 8, accuracy: 0.0001)
    }

    /// 축을 좁게 잡아 기본 구간이 밖으로 나가면, 손잡이를 잡을 수 있도록 축 안으로 잘라 넣는다.
    func testDefaultWindowIsClampedIntoANarrowAxis() {
        let narrow = DiarySleepAxis(startHour: 0, endHour: 6, tickInterval: 1)

        let window = DiarySleepWindowPolicy.defaultWindow(for: day, axis: narrow, calendar: calendar)

        XCTAssertGreaterThanOrEqual(window.start, narrow.start(of: day, calendar: calendar))
        XCTAssertLessThanOrEqual(window.end, narrow.end(of: day, calendar: calendar))
        XCTAssertGreaterThanOrEqual(
            window.duration,
            Double(DiarySleepWindowPolicy.minimumMinutes) * 60,
            "잘라 넣어도 손잡이 둘이 겹치지 않는다"
        )
    }

    // MARK: - 인사이트 연결

    /// 시각이 있는 기록과 길이만 있는 옛 기록이 같은 축 위에 함께 선다.
    func testInsightsPlaceRecordedAndLegacySleepOnTheSameAxis() {
        let previous = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        let entries = [
            DiaryDay(
                day: previous, body: "", stress: nil,
                sleepHours: 8, sleepSource: .manual
            ),
            DiaryDay(
                day: day, body: "", stress: nil,
                sleepHours: 7.5, sleepSource: .manual,
                sleepStart: time(9, 5, 23, 40), sleepEnd: time(9, 6, 7, 10)
            )
        ]

        let snapshot = DiaryInsightsBuilder.build(
            entries: entries,
            start: previous,
            end: calendar.date(byAdding: .day, value: 1, to: day) ?? day,
            axis: axis,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.sleepWindowPoints.count, 2, "길이만 있는 옛 기록도 빠지지 않는다")
        XCTAssertEqual(snapshot.sleepWindowPoints.last?.hours ?? 0, 7.5, accuracy: 0.0001)
        let recorded = try? XCTUnwrap(snapshot.sleepWindowPoints.last)
        // 축이 21시에서 시작하므로 23:40 은 2시간 40분 지점, 07:10 은 10시간 10분 지점이다.
        XCTAssertEqual(recorded?.startFraction ?? 0, (2 + 40.0 / 60) / 15.0, accuracy: 0.0001)
        XCTAssertEqual(recorded?.endFraction ?? 0, (10 + 10.0 / 60) / 15.0, accuracy: 0.0001)
    }

    func testInsightsSkipDaysWithoutAnySleepRecord() {
        let entries = [
            DiaryDay(
                day: day, body: "", stress: nil, sleepHours: nil, sleepSource: nil,
                moodRecords: [DiaryMoodRecord(slot: .wholeDay, mood: .happy)]
            )
        ]

        let snapshot = DiaryInsightsBuilder.build(
            entries: entries,
            start: day,
            end: calendar.date(byAdding: .day, value: 1, to: day) ?? day,
            axis: axis,
            calendar: calendar
        )

        XCTAssertTrue(snapshot.sleepWindowPoints.isEmpty)
        XCTAssertEqual(snapshot.moodPoints.count, 1)
    }
}
