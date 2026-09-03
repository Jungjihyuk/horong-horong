import XCTest
@testable import 호롱호롱

/// **화면도 건강 앱도 없이** 일기 화면의 규칙을 검사한다.
///
/// 특히 «직접 입력한 수면 시간을 건강 앱 값이 덮어쓰지 않는다» 는, 예전 구조에서는
/// 실기에서 건강 앱 권한을 켜야만 확인할 수 있었다.
@MainActor
final class DiaryViewModelTests: XCTestCase {
    private final class FakeRepository: DiaryRepository {
        var days: [Date: DiaryDay] = [:]
        private(set) var monthFetchCount = 0
        private let calendar = Calendar.current

        func entries(inMonthOf date: Date) throws -> [DiaryDay] {
            monthFetchCount += 1
            return days.values
                .filter { calendar.isDate($0.day, equalTo: date, toGranularity: .month) }
                .sorted { $0.day > $1.day }
        }

        func entry(on day: Date) throws -> DiaryDay? { days[calendar.startOfDay(for: day)] }

        @discardableResult
        func setBody(on day: Date, body: String) throws -> DiaryDay {
            upsert(day) { DiaryDay(day: $0.day, body: body, mood: $0.mood, stress: $0.stress, sleepHours: $0.sleepHours, sleepSource: $0.sleepSource) }
        }

        @discardableResult
        func setMood(on day: Date, mood: DiaryMood?) throws -> DiaryDay {
            upsert(day) { DiaryDay(day: $0.day, body: $0.body, mood: mood, stress: $0.stress, sleepHours: $0.sleepHours, sleepSource: $0.sleepSource) }
        }

        @discardableResult
        func setStress(on day: Date, stress: Int?) throws -> DiaryDay {
            upsert(day) { DiaryDay(day: $0.day, body: $0.body, mood: $0.mood, stress: stress, sleepHours: $0.sleepHours, sleepSource: $0.sleepSource) }
        }

        @discardableResult
        func setSleep(on day: Date, hours: Double, source: DiarySleepSource) throws -> DiaryDay {
            upsert(day) { DiaryDay(day: $0.day, body: $0.body, mood: $0.mood, stress: $0.stress, sleepHours: hours, sleepSource: source) }
        }

        /// 실제 구현과 같이 «없으면 만들고 있으면 고친다».
        private func upsert(_ day: Date, _ change: (DiaryDay) -> DiaryDay) -> DiaryDay {
            let normalized = calendar.startOfDay(for: day)
            let base = days[normalized]
                ?? DiaryDay(day: normalized, body: "", mood: nil, stress: nil, sleepHours: nil, sleepSource: nil)
            let updated = change(base)
            days[normalized] = updated
            return updated
        }
    }

    private final class FakeSleepGateway: SleepGateway {
        var isAvailable = true
        var hours: Double? = 6.5
        private(set) var callCount = 0

        func sleepHours(on day: Date, calendar: Calendar) async -> Double? {
            callCount += 1
            return hours
        }
    }

    private func day(_ offset: Int) -> Date {
        Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        )
    }

    private func make() -> (DiaryViewModel, FakeRepository, FakeSleepGateway) {
        let repository = FakeRepository()
        let sleep = FakeSleepGateway()
        return (DiaryViewModel(repository: repository, sleep: sleep), repository, sleep)
    }

    // MARK: - 달 단위 조회

    /// 보고 있는 달만 가져온다. 예전에는 전량을 가져와 사전을 지었다.
    func testReloadLoadsOnlyVisibleMonth() {
        let (viewModel, repository, _) = make()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: today) ?? today
        repository.days = [
            today: DiaryDay(day: today, body: "오늘", mood: nil, stress: nil, sleepHours: nil, sleepSource: nil),
            lastMonth: DiaryDay(day: lastMonth, body: "지난달", mood: nil, stress: nil, sleepHours: nil, sleepSource: nil)
        ]

        viewModel.reload()

        XCTAssertEqual(viewModel.writtenCount, 1)
        XCTAssertNotNil(viewModel.entry(on: today))
        XCTAssertNil(viewModel.entry(on: lastMonth))
    }

    func testShiftMonthRefetches() {
        let (viewModel, repository, _) = make()
        viewModel.reload()
        let before = repository.monthFetchCount

        viewModel.shiftMonth(-1)

        XCTAssertGreaterThan(repository.monthFetchCount, before)
        XCTAssertFalse(
            Calendar.current.isDate(viewModel.visibleMonth, equalTo: Date(), toGranularity: .month)
        )
    }

    /// 다른 달의 날을 고르면 달력도 따라간다 — 고른 날이 안 보이면 안 된다.
    func testSelectingOtherMonthMovesCalendar() {
        let (viewModel, _, _) = make()
        viewModel.reload()
        let target = Calendar.current.date(byAdding: .month, value: -2, to: Date()) ?? Date()

        viewModel.select(target)

        XCTAssertTrue(Calendar.current.isDate(viewModel.visibleMonth, equalTo: target, toGranularity: .month))
        XCTAssertTrue(Calendar.current.isDate(viewModel.selectedDay, inSameDayAs: target))
    }

    // MARK: - 기록

    /// 같은 기분을 다시 누르면 해제된다.
    func testMoodTogglesOff() {
        let (viewModel, _, _) = make()
        viewModel.reload()
        let mood = DiaryMood.allCases[0]

        viewModel.setMood(mood)
        XCTAssertEqual(viewModel.selected?.mood, mood)

        viewModel.setMood(mood)
        XCTAssertNil(viewModel.selected?.mood)
    }

    func testStressTogglesOff() {
        let (viewModel, _, _) = make()
        viewModel.reload()

        viewModel.setStress(3)
        XCTAssertEqual(viewModel.selected?.stress, 3)

        viewModel.setStress(3)
        XCTAssertNil(viewModel.selected?.stress)
    }

    /// 쓰기 한 번이 달력에도 바로 반영된다 — 목록을 다시 읽지 않고.
    func testWriteUpdatesCalendarWithoutRefetch() {
        let (viewModel, repository, _) = make()
        viewModel.reload()
        let before = repository.monthFetchCount

        viewModel.setStress(2)

        XCTAssertEqual(repository.monthFetchCount, before, "다시 읽지 않는다")
        XCTAssertEqual(viewModel.entry(on: viewModel.selectedDay)?.stress, 2)
        XCTAssertEqual(viewModel.writtenCount, 1)
    }

    func testFlushSavesDraft() {
        let (viewModel, repository, _) = make()
        viewModel.reload()

        viewModel.bodyDraft = "오늘은 비가 왔다"
        viewModel.flush()

        XCTAssertEqual(repository.days[viewModel.selectedDay]?.body, "오늘은 비가 왔다")
    }

    /// 날을 바꾸면 그 전에 쓰던 것이 저장되고, 새 날의 본문이 올라온다.
    func testSelectFlushesAndLoadsDraft() {
        let (viewModel, repository, _) = make()
        let yesterday = day(-1)
        repository.days[yesterday] = DiaryDay(
            day: yesterday, body: "어제 쓴 글", mood: nil, stress: nil, sleepHours: nil, sleepSource: nil
        )
        viewModel.reload()

        viewModel.bodyDraft = "오늘 쓴 글"
        viewModel.select(yesterday)

        XCTAssertEqual(repository.days[day(0)]?.body, "오늘 쓴 글", "떠나기 전에 저장한다")
        XCTAssertEqual(viewModel.bodyDraft, "어제 쓴 글")
    }

    // MARK: - 수면

    func testPullSleepFillsWhenEmpty() async {
        let (viewModel, _, sleep) = make()
        viewModel.reload()

        viewModel.pullSleepIfNeeded()
        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(viewModel.selected?.sleepHours, 6.5)
        XCTAssertEqual(viewModel.selected?.sleepSource, .healthKit)
        XCTAssertEqual(sleep.callCount, 1)
    }

    /// **직접 입력한 값을 건강 앱이 덮어쓰지 않는다.**
    func testManualSleepIsNotOverwritten() async {
        let (viewModel, _, sleep) = make()
        viewModel.reload()
        viewModel.setSleepHours(8)

        viewModel.pullSleepIfNeeded()
        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(viewModel.selected?.sleepHours, 8)
        XCTAssertEqual(viewModel.selected?.sleepSource, .manual)
        XCTAssertEqual(sleep.callCount, 0, "물어보지도 않는다")
    }

    /// 사용자가 «가져오기» 를 직접 누르면 그때는 덮어쓴다.
    func testForcedPullOverwritesManual() async {
        let (viewModel, _, _) = make()
        viewModel.reload()
        viewModel.setSleepHours(8)

        viewModel.pullSleep(force: true)
        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(viewModel.selected?.sleepHours, 6.5)
        XCTAssertEqual(viewModel.selected?.sleepSource, .healthKit)
    }

    /// 건강 앱에 그날 기록이 없으면 아무것도 안 만든다.
    func testMissingSleepLeavesEntryUntouched() async {
        let (viewModel, repository, sleep) = make()
        sleep.hours = nil
        viewModel.reload()

        viewModel.pullSleepIfNeeded()
        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertTrue(repository.days.isEmpty)
        XCTAssertFalse(viewModel.isPullingSleep)
    }
}
