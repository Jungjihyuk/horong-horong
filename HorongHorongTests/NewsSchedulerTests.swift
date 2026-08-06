import SwiftData
import XCTest
@testable import 호롱호롱

/// `NewsSchedulePlan` 은 순수 함수 모음이라 고정 `Calendar` / `Date` 로 전부 검증할 수 있다.
final class NewsSchedulePlanTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    // MARK: - initialSlot

    func testInitialSlotForManualIsNil() {
        XCTAssertNil(NewsSchedulePlan.initialSlot(
            from: date(2026, 8, 6, 10, 0),
            mode: .manual,
            dailyHour: 9,
            dailyMinute: 0,
            intervalHours: 3,
            calendar: calendar
        ))
    }

    func testInitialSlotForDailyUsesTodayWhenTimeHasNotPassed() {
        let slot = NewsSchedulePlan.initialSlot(
            from: date(2026, 8, 6, 7, 30),
            mode: .dailyAt,
            dailyHour: 9,
            dailyMinute: 0,
            intervalHours: 3,
            calendar: calendar
        )
        XCTAssertEqual(slot, date(2026, 8, 6, 9, 0))
    }

    func testInitialSlotForDailyRollsToTomorrowWhenTimeHasPassed() {
        let slot = NewsSchedulePlan.initialSlot(
            from: date(2026, 8, 6, 10, 0),
            mode: .dailyAt,
            dailyHour: 9,
            dailyMinute: 0,
            intervalHours: 3,
            calendar: calendar
        )
        XCTAssertEqual(slot, date(2026, 8, 7, 9, 0))
    }

    /// 간격 격자는 **시작 시각**을 기준으로 만들어진다. 버튼을 누른 시각과 무관하다.
    func testIntervalGridIsAnchoredToStartTimeNotToNow() {
        // 시작 12:00 · 3시간 → 격자 12·15·18·21. 16:47 에 켜도 다음은 18:00.
        let slot = NewsSchedulePlan.initialSlot(
            from: date(2026, 8, 6, 16, 47),
            mode: .interval,
            dailyHour: 9,
            dailyMinute: 0,
            intervalHours: 3,
            intervalStartHour: 12,
            intervalStartMinute: 0,
            calendar: calendar
        )
        XCTAssertEqual(slot, date(2026, 8, 6, 18, 0))
    }

    /// 시작 시각이 아직 오지 않았으면 그 시각이 첫 슬롯이다.
    func testIntervalGridUsesStartTimeWhenItIsStillAhead() {
        let slot = NewsSchedulePlan.initialSlot(
            from: date(2026, 8, 6, 9, 30),
            mode: .interval,
            dailyHour: 9,
            dailyMinute: 0,
            intervalHours: 3,
            intervalStartHour: 12,
            intervalStartMinute: 0,
            calendar: calendar
        )
        XCTAssertEqual(slot, date(2026, 8, 6, 12, 0))
    }

    /// `특정 시각`(09:00)은 간격 모드의 격자에 전혀 영향을 주지 않는다.
    func testDailyTimeDoesNotAffectIntervalGrid() {
        let withNineAM = NewsSchedulePlan.initialSlot(
            from: date(2026, 8, 6, 16, 47), mode: .interval,
            dailyHour: 9, dailyMinute: 0, intervalHours: 3,
            intervalStartHour: 12, intervalStartMinute: 0, calendar: calendar
        )
        let withElevenPM = NewsSchedulePlan.initialSlot(
            from: date(2026, 8, 6, 16, 47), mode: .interval,
            dailyHour: 23, dailyMinute: 45, intervalHours: 3,
            intervalStartHour: 12, intervalStartMinute: 0, calendar: calendar
        )
        XCTAssertEqual(withNineAM, withElevenPM)
        XCTAssertEqual(withNineAM, date(2026, 8, 6, 18, 0))
    }

    /// 24로 나누어떨어지지 않는 간격은 날짜를 넘어가며 계속 이어진다 — 매일 리셋되지 않는다.
    func testNonDivisorIntervalContinuesAcrossMidnight() {
        // 시작 12:00 · 5시간 → 12 · 17 · 22 · (다음날) 03 · 08 · 13
        let slot = NewsSchedulePlan.initialSlot(
            from: date(2026, 8, 6, 23, 30),
            mode: .interval,
            dailyHour: 9, dailyMinute: 0, intervalHours: 5,
            intervalStartHour: 12, intervalStartMinute: 0, calendar: calendar
        )
        XCTAssertEqual(slot, date(2026, 8, 7, 3, 0))
    }

    /// 시작 시각 정각에 켜면 즉시 돌지 않고 한 칸 뒤부터 — 설정을 만지자마자 파이프라인이 도는 걸 피한다.
    func testIntervalGridSkipsImmediateRunAtExactStartTime() {
        let slot = NewsSchedulePlan.initialSlot(
            from: date(2026, 8, 6, 12, 0),
            mode: .interval,
            dailyHour: 9, dailyMinute: 0, intervalHours: 3,
            intervalStartHour: 12, intervalStartMinute: 0, calendar: calendar
        )
        XCTAssertEqual(slot, date(2026, 8, 6, 15, 0))
    }

    // MARK: - displayText

    func testDisplayTextUsesRelativeDayNames() {
        let now = date(2026, 8, 6, 10, 0)
        XCTAssertEqual(
            NewsSchedulePlan.displayText(for: date(2026, 8, 6, 18, 0), now: now, calendar: calendar),
            "오늘 18:00"
        )
        XCTAssertEqual(
            NewsSchedulePlan.displayText(for: date(2026, 8, 7, 9, 5), now: now, calendar: calendar),
            "내일 09:05"
        )
        XCTAssertEqual(
            NewsSchedulePlan.displayText(for: date(2026, 8, 9, 18, 0), now: now, calendar: calendar),
            "8월 9일 18:00"
        )
    }

    // MARK: - advance

    func testAdvanceMovesOneGridStep() {
        XCTAssertEqual(
            NewsSchedulePlan.advance(slot: date(2026, 8, 6, 15, 0), mode: .interval, intervalHours: 3, calendar: calendar),
            date(2026, 8, 6, 18, 0)
        )
        XCTAssertEqual(
            NewsSchedulePlan.advance(slot: date(2026, 8, 6, 9, 0), mode: .dailyAt, intervalHours: 3, calendar: calendar),
            date(2026, 8, 7, 9, 0)
        )
    }

    // MARK: - catchUp

    func testCatchUpKeepsFutureSlotUntouched() {
        let slot = date(2026, 8, 6, 15, 0)
        let result = NewsSchedulePlan.catchUp(
            slot: slot, now: date(2026, 8, 6, 14, 0), mode: .interval, intervalHours: 3, calendar: calendar
        )
        XCTAssertEqual(result.next, slot)
        XCTAssertNil(result.missedSlot)
    }

    /// 격자가 유지되어야 한다. 10시간을 방치해도 다음 슬롯은 `현재 + 3시간` 이 아니라 격자 위 지점이다.
    func testCatchUpPreservesTheGridAfterLongGap() {
        let result = NewsSchedulePlan.catchUp(
            slot: date(2026, 8, 6, 12, 0),
            now: date(2026, 8, 6, 22, 30),
            mode: .interval,
            intervalHours: 3,
            calendar: calendar
        )
        // 12:00 격자 → 15, 18, 21, 24. 22:30 기준 다음은 다음날 00:00.
        XCTAssertEqual(result.next, date(2026, 8, 7, 0, 0))
        XCTAssertEqual(result.missedSlot, date(2026, 8, 6, 21, 0))
    }

    /// 며칠을 놓쳐도 실행 후보는 하나만 돌려준다 — 몰아서 실행되면 안 된다.
    func testCatchUpReportsOnlyTheMostRecentMissedSlot() {
        let result = NewsSchedulePlan.catchUp(
            slot: date(2026, 8, 3, 9, 0),
            now: date(2026, 8, 6, 10, 0),
            mode: .dailyAt,
            intervalHours: 3,
            calendar: calendar
        )
        XCTAssertEqual(result.missedSlot, date(2026, 8, 6, 9, 0))
        XCTAssertEqual(result.next, date(2026, 8, 7, 9, 0))
    }

    /// 바쁜 루프를 막는 핵심 불변식: `next` 는 언제나 `now` 보다 미래다.
    func testCatchUpAlwaysReturnsFutureSlot() {
        let now = date(2026, 8, 6, 14, 0)
        for hours in 1...24 {
            for daysAgo in [0, 1, 7, 400] {
                let slot = calendar.date(byAdding: .day, value: -daysAgo, to: date(2026, 8, 6, 0, 0))!
                let result = NewsSchedulePlan.catchUp(
                    slot: slot, now: now, mode: .interval, intervalHours: hours, calendar: calendar
                )
                XCTAssertGreaterThan(result.next, now, "interval=\(hours), daysAgo=\(daysAgo)")
            }
        }
    }

    func testCatchUpOnExactSlotBoundaryTreatsSlotAsDue() {
        let slot = date(2026, 8, 6, 15, 0)
        let result = NewsSchedulePlan.catchUp(
            slot: slot, now: slot, mode: .interval, intervalHours: 3, calendar: calendar
        )
        XCTAssertEqual(result.missedSlot, slot)
        XCTAssertEqual(result.next, date(2026, 8, 6, 18, 0))
    }

    // MARK: - grace / shouldSkip

    func testGraceIsHalfTheIntervalUpToTheCap() {
        XCTAssertEqual(NewsSchedulePlan.grace(mode: .interval, intervalHours: 3), 90 * 60)
        XCTAssertEqual(NewsSchedulePlan.grace(mode: .interval, intervalHours: 1), 30 * 60)
        // 상한에서 잘린다.
        XCTAssertEqual(NewsSchedulePlan.grace(mode: .interval, intervalHours: 12), NewsSchedulePlan.graceCap)
        XCTAssertEqual(NewsSchedulePlan.grace(mode: .dailyAt, intervalHours: 3), NewsSchedulePlan.graceCap)
        XCTAssertEqual(NewsSchedulePlan.grace(mode: .manual, intervalHours: 3), 0)
    }

    /// 15:00 슬롯 직전인 14:58 에 직접 눌렀다면 그 슬롯은 건너뛴다.
    func testShouldSkipWhenCollectedJustBeforeTheSlot() {
        XCTAssertTrue(NewsSchedulePlan.shouldSkip(
            slot: date(2026, 8, 6, 15, 0),
            lastRunAt: date(2026, 8, 6, 14, 58),
            mode: .interval,
            intervalHours: 3
        ))
    }

    /// 12:30 은 유예 창(90분) 밖이므로 15:00 슬롯은 정상 실행된다.
    func testShouldNotSkipWhenLastRunIsOutsideTheGraceWindow() {
        XCTAssertFalse(NewsSchedulePlan.shouldSkip(
            slot: date(2026, 8, 6, 15, 0),
            lastRunAt: date(2026, 8, 6, 12, 30),
            mode: .interval,
            intervalHours: 3
        ))
    }

    func testShouldNotSkipWhenNeverCollected() {
        XCTAssertFalse(NewsSchedulePlan.shouldSkip(
            slot: date(2026, 8, 6, 15, 0), lastRunAt: nil, mode: .interval, intervalHours: 3
        ))
    }

    /// 매일 09:00 인데 전날 21:30 에 눌렀다면 건너뛰면 안 된다 — 상한이 없으면 12시간이 창이 되어 버린다.
    func testDailyModeDoesNotSkipForYesterdayEveningRun() {
        XCTAssertFalse(NewsSchedulePlan.shouldSkip(
            slot: date(2026, 8, 6, 9, 0),
            lastRunAt: date(2026, 8, 5, 21, 30),
            mode: .dailyAt,
            intervalHours: 3
        ))
    }

    func testDailyModeSkipsForRunShortlyBeforeTheSlot() {
        XCTAssertTrue(NewsSchedulePlan.shouldSkip(
            slot: date(2026, 8, 6, 9, 0),
            lastRunAt: date(2026, 8, 6, 8, 50),
            mode: .dailyAt,
            intervalHours: 3
        ))
    }

    // MARK: - manual / 경계

    func testManualModeNeverProducesWork() {
        let slot = date(2026, 8, 6, 12, 0)
        let result = NewsSchedulePlan.catchUp(
            slot: slot, now: date(2026, 8, 6, 20, 0), mode: .manual, intervalHours: 3, calendar: calendar
        )
        XCTAssertNil(result.missedSlot)
        XCTAssertFalse(NewsSchedulePlan.shouldSkip(
            slot: slot, lastRunAt: date(2026, 8, 6, 11, 59), mode: .manual, intervalHours: 3
        ))
    }

    func testNormalizedIntervalHoursClampsToSupportedRange() {
        XCTAssertEqual(NewsSchedulePlan.normalizedIntervalHours(0), 1)
        XCTAssertEqual(NewsSchedulePlan.normalizedIntervalHours(-5), 1)
        XCTAssertEqual(NewsSchedulePlan.normalizedIntervalHours(3), 3)
        XCTAssertEqual(NewsSchedulePlan.normalizedIntervalHours(99), 24)
    }

    // MARK: - 모드 마이그레이션

    func testLegacyScheduleValuesMapToNewModes() {
        XCTAssertEqual(Constants.NewsScheduleMode.normalized(rawValue: "hourly"), .interval)
        XCTAssertEqual(Constants.NewsScheduleMode.normalized(rawValue: "daily"), .dailyAt)
        XCTAssertEqual(Constants.NewsScheduleMode.normalized(rawValue: "manual"), .manual)
        XCTAssertEqual(Constants.NewsScheduleMode.normalized(rawValue: "무엇인지 모를 값"), .manual)
        XCTAssertEqual(Constants.NewsScheduleMode.normalized(rawValue: "interval"), .interval)
        XCTAssertEqual(Constants.NewsScheduleMode.normalized(rawValue: "dailyAt"), .dailyAt)
    }
}

/// 모드를 오가며 눌러도 격자가 매번 새로 잡히는지 — 실제 `NewsScheduler` 를 돌려 확인한다.
@MainActor
final class NewsSchedulerModeSwitchTests: XCTestCase {
    private let startHour = 12
    private let startMinute = 0

    private var suiteName = ""
    private var defaults: UserDefaults!
    private var scheduler: NewsScheduler!
    private var service: NewsPipelineService!
    private var container: ModelContainer!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "NewsSchedulerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        let schema = Schema([NewsJob.self, NewsReportIndex.self])
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        service = NewsPipelineService()
        scheduler = NewsScheduler(defaults: defaults)

        defaults.set(18, forKey: Constants.NewsStorageKey.scheduleDailyHour)
        defaults.set(18, forKey: Constants.NewsStorageKey.scheduleDailyMinute)
        defaults.set(3, forKey: Constants.NewsStorageKey.scheduleIntervalHours)
        defaults.set(startHour, forKey: Constants.NewsStorageKey.scheduleIntervalStartHour)
        defaults.set(startMinute, forKey: Constants.NewsStorageKey.scheduleIntervalStartMinute)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func setMode(_ mode: Constants.NewsScheduleMode) {
        defaults.set(mode.rawValue, forKey: Constants.NewsStorageKey.schedule)
        settle()
    }

    /// `UserDefaults.didChangeNotification` 은 메인 큐로 비동기 전달된다.
    /// 런루프를 한 번 돌려 관찰자가 실제로 반응하게 한다.
    private func settle() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    private var nextSlot: Date? {
        let raw = defaults.double(forKey: Constants.NewsStorageKey.scheduleNextSlotAt)
        return raw > 0 ? Date(timeIntervalSince1970: raw) : nil
    }

    /// 벽시계 시각과 무관하게 검증하려면 "격자 위에 있는가" 를 봐야 한다.
    /// 시작 시각을 기준점으로 잡고 간격으로 나눈 나머지가 0이어야 한다.
    private func assertOnIntervalGrid(
        _ slot: Date,
        intervalHours: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertGreaterThan(slot, Date(), "다음 슬롯은 미래여야 한다", file: file, line: line)
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = startHour
        components.minute = startMinute
        components.second = 0
        let anchor = Calendar.current.date(from: components)!
        let step = Double(intervalHours * 3600)
        let remainder = abs(slot.timeIntervalSince(anchor).truncatingRemainder(dividingBy: step))
        XCTAssertEqual(
            min(remainder, step - remainder), 0, accuracy: 1,
            "슬롯 \(slot) 이 \(intervalHours)시간 격자 위에 있지 않다",
            file: file, line: line
        )
    }

    private func assertDailySlotAtEighteenEighteen(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let slot = try XCTUnwrap(nextSlot, file: file, line: line)
        let components = Calendar.current.dateComponents([.hour, .minute], from: slot)
        XCTAssertEqual(components.hour, 18, file: file, line: line)
        XCTAssertEqual(components.minute, 18, file: file, line: line)
    }

    func testSwitchingModesBackAndForthAlwaysRebuildsTheGrid() throws {
        defaults.set(Constants.NewsScheduleMode.manual.rawValue, forKey: Constants.NewsStorageKey.schedule)
        scheduler.start(pipelineService: service, modelContext: container.mainContext)
        XCTAssertNil(nextSlot, "manual 모드에서는 예약이 없어야 한다")

        setMode(.dailyAt)
        try assertDailySlotAtEighteenEighteen()

        setMode(.interval)
        assertOnIntervalGrid(try XCTUnwrap(nextSlot), intervalHours: 3)

        // 되돌아와도 특정 시각 설정값이 살아 있어야 한다.
        setMode(.dailyAt)
        try assertDailySlotAtEighteenEighteen()

        setMode(.interval)
        assertOnIntervalGrid(try XCTUnwrap(nextSlot), intervalHours: 3)

        setMode(.manual)
        XCTAssertNil(nextSlot, "manual 로 돌아오면 예약이 지워져야 한다")

        setMode(.dailyAt)
        XCTAssertNotNil(nextSlot, "manual 을 거친 뒤에도 다시 예약되어야 한다")
    }

    /// 간격 값만 바꿔도 격자가 새 간격으로 다시 잡히는지.
    func testChangingIntervalRebuildsTheGrid() throws {
        defaults.set(Constants.NewsScheduleMode.interval.rawValue, forKey: Constants.NewsStorageKey.schedule)
        scheduler.start(pipelineService: service, modelContext: container.mainContext)
        assertOnIntervalGrid(try XCTUnwrap(nextSlot), intervalHours: 3)

        // 3시간 격자와 겹치는 지점이 적은 값으로 바꿔 실제로 다시 계산됐는지 본다.
        defaults.set(5, forKey: Constants.NewsStorageKey.scheduleIntervalHours)
        settle()
        assertOnIntervalGrid(try XCTUnwrap(nextSlot), intervalHours: 5)
    }

    /// 시작 시각을 바꾸면 격자 전체가 그 시각 기준으로 옮겨가야 한다.
    func testChangingStartTimeMovesTheWholeGrid() throws {
        defaults.set(Constants.NewsScheduleMode.interval.rawValue, forKey: Constants.NewsStorageKey.schedule)
        scheduler.start(pipelineService: service, modelContext: container.mainContext)
        let before = try XCTUnwrap(nextSlot)

        // 12:00 기준 3시간 격자는 정각에 떨어진다. 시작을 12:20 으로 옮기면 20분에 떨어져야 한다.
        defaults.set(20, forKey: Constants.NewsStorageKey.scheduleIntervalStartMinute)
        settle()
        let after = try XCTUnwrap(nextSlot)

        XCTAssertEqual(Calendar.current.component(.minute, from: before), 0)
        XCTAssertEqual(Calendar.current.component(.minute, from: after), 20)
    }

    /// 실제로 겪은 상황의 재현:
    /// 18:18 에 수집한 뒤 20:00 시작 · 6시간 간격을 새로 설정하면, 20:00 이 유예 창(2시간)에
    /// 걸려 조용히 사라졌다. 설정 확정 이전의 수집은 세지 않아야 한다.
    func testGraceWindowIgnoresCollectionsFromBeforeTheScheduleWasConfigured() {
        // 설정을 바꾸기 10분 전에 수집이 있었던 상황.
        let before = Date().addingTimeInterval(-600)
        defaults.set(before.timeIntervalSince1970, forKey: Constants.NewsStorageKey.scheduleLastRunAt)
        defaults.set(Constants.NewsScheduleMode.interval.rawValue, forKey: Constants.NewsStorageKey.schedule)
        scheduler.start(pipelineService: service, modelContext: container.mainContext)

        // 사용자가 간격을 바꿔 스케줄을 새로 확정한다.
        defaults.set(6, forKey: Constants.NewsStorageKey.scheduleIntervalHours)
        settle()

        let configuredAt = defaults.double(forKey: Constants.NewsStorageKey.scheduleConfiguredAt)
        XCTAssertGreaterThan(configuredAt, 0, "설정 확정 시각이 기록되어야 한다")
        XCTAssertGreaterThan(
            configuredAt, before.timeIntervalSince1970,
            "확정 시각이 이전 수집보다 뒤여야 옛 기록을 걸러낼 수 있다"
        )
    }

    /// `특정 시각` 값을 바꿔도 간격 모드의 격자는 흔들리지 않아야 한다.
    func testDailyTimeChangeDoesNotMoveIntervalGrid() throws {
        defaults.set(Constants.NewsScheduleMode.interval.rawValue, forKey: Constants.NewsStorageKey.schedule)
        scheduler.start(pipelineService: service, modelContext: container.mainContext)
        let before = try XCTUnwrap(nextSlot)

        defaults.set(6, forKey: Constants.NewsStorageKey.scheduleDailyHour)
        defaults.set(45, forKey: Constants.NewsStorageKey.scheduleDailyMinute)
        settle()

        XCTAssertEqual(try XCTUnwrap(nextSlot), before, "특정 시각 설정은 간격 격자에 영향을 주면 안 된다")
    }
}
