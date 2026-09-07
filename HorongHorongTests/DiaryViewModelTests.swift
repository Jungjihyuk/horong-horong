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

        func entries(from start: Date, to end: Date) throws -> [DiaryDay] {
            days.values
                .filter { $0.day >= start && $0.day < end }
                .sorted { $0.day > $1.day }
        }

        func entry(on day: Date) throws -> DiaryDay? { days[calendar.startOfDay(for: day)] }

        @discardableResult
        func setBody(on day: Date, body: String) throws -> DiaryDay {
            upsert(day) { $0.with(body: body) }
        }

        @discardableResult
        func setMood(on day: Date, slot: DiaryMoodSlot, mood: DiaryMood?) throws -> DiaryDay {
            upsert(day) { base in
                guard let mood else { return base.removingRecord(slot) }
                let existing = base.record(slot)
                return base.settingRecord(
                    DiaryMoodRecord(slot: slot, mood: mood, cause: existing?.cause, intensity: existing?.intensity)
                )
            }
        }

        @discardableResult
        func setCause(on day: Date, slot: DiaryMoodSlot, cause: DiaryCause?) throws -> DiaryDay {
            upsert(day) { base in
                guard let existing = base.record(slot) else { return base }
                return base.settingRecord(
                    DiaryMoodRecord(slot: slot, mood: existing.mood, cause: cause, intensity: existing.intensity)
                )
            }
        }

        @discardableResult
        func setIntensity(on day: Date, slot: DiaryMoodSlot, intensity: Int?) throws -> DiaryDay {
            upsert(day) { base in
                guard let existing = base.record(slot) else { return base }
                return base.settingRecord(
                    DiaryMoodRecord(slot: slot, mood: existing.mood, cause: existing.cause, intensity: intensity)
                )
            }
        }

        @discardableResult
        func setStress(on day: Date, stress: Int?) throws -> DiaryDay {
            upsert(day) { $0.with(stress: stress) }
        }

        @discardableResult
        func setSleep(on day: Date, window: DiarySleepWindow?, source: DiarySleepSource) throws -> DiaryDay {
            upsert(day) { $0.with(window: window, source: source) }
        }

        /// 실제 구현과 같이 «없으면 만들고 있으면 고친다».
        private func upsert(_ day: Date, _ change: (DiaryDay) -> DiaryDay) -> DiaryDay {
            let normalized = calendar.startOfDay(for: day)
            let base = days[normalized]
                ?? DiaryDay(day: normalized, body: "", stress: nil, sleepHours: nil, sleepSource: nil)
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
            today: DiaryDay(day: today, body: "오늘", stress: nil, sleepHours: nil, sleepSource: nil),
            lastMonth: DiaryDay(day: lastMonth, body: "지난달", stress: nil, sleepHours: nil, sleepSource: nil)
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

        viewModel.setMood(mood, in: .wholeDay)
        XCTAssertEqual(viewModel.selected?.record(.wholeDay)?.mood, mood)

        viewModel.setMood(mood, in: .wholeDay)
        XCTAssertNil(viewModel.selected?.record(.wholeDay))
    }

    /// 감정을 지우면 그 칸의 원인·강도도 함께 사라진다 —
    /// «무엇이었는지 모르는 채 남은 강도 4» 는 읽을 수 없는 기록이다.
    func testClearingMoodAlsoClearsCauseAndIntensity() {
        let (viewModel, _, _) = make()
        viewModel.reload()

        viewModel.setMood(.happy, in: .wholeDay)
        viewModel.setIntensity(4, in: .wholeDay)
        viewModel.setCause(.work, in: .wholeDay)
        viewModel.setMood(.happy, in: .wholeDay)

        XCTAssertNil(viewModel.selected?.record(.wholeDay))
        XCTAssertTrue(viewModel.selected?.moodRecords.isEmpty ?? false)
    }

    /// **세 칸은 서로를 건드리지 않는다.** 하루에 하나만 적던 시절의 핵심 제약이 풀린 자리다.
    func testThreeSlotsAreIndependent() {
        let (viewModel, _, _) = make()
        viewModel.reload()

        viewModel.setMood(.happy, in: .morning)
        viewModel.setMood(.angry, in: .afternoon)
        viewModel.setMood(.comfort, in: .wholeDay)

        XCTAssertEqual(viewModel.selected?.record(.morning)?.mood, .happy)
        XCTAssertEqual(viewModel.selected?.record(.afternoon)?.mood, .angry)
        XCTAssertEqual(viewModel.selected?.record(.wholeDay)?.mood, .comfort)

        viewModel.setMood(.angry, in: .afternoon)

        XCTAssertEqual(viewModel.selected?.record(.morning)?.mood, .happy, "다른 칸은 그대로다")
        XCTAssertNil(viewModel.selected?.record(.afternoon))
        XCTAssertEqual(viewModel.selected?.record(.wholeDay)?.mood, .comfort)
    }

    /// 한 칸만 적어도, 두 칸만 적어도 된다.
    func testPartialSlotsAreAllowed() {
        let (viewModel, _, _) = make()
        viewModel.reload()

        viewModel.setMood(.anxious, in: .afternoon)

        XCTAssertEqual(viewModel.selected?.moodRecords.count, 1)
        XCTAssertNil(viewModel.selected?.record(.morning))
        XCTAssertNil(viewModel.selected?.record(.wholeDay))
    }

    /// 기록은 슬롯 순(오전 → 오후 → 하루)으로 정렬돼 나온다 — 적은 순서와 무관하게.
    func testMoodRecordsAreSortedBySlotOrder() {
        let (viewModel, _, _) = make()
        viewModel.reload()

        viewModel.setMood(.comfort, in: .wholeDay)
        viewModel.setMood(.happy, in: .morning)
        viewModel.setMood(.angry, in: .afternoon)

        XCTAssertEqual(viewModel.selected?.moodRecords.map(\.slot), [.morning, .afternoon, .wholeDay])
    }

    /// 달력 한 칸이 보여 줄 얼굴은 넓은 범위부터 고른다.
    func testRepresentativeMoodPrefersWholeDay() {
        let (viewModel, _, _) = make()
        viewModel.reload()

        viewModel.setMood(.happy, in: .morning)
        XCTAssertEqual(viewModel.selected?.representativeMood, .happy)

        viewModel.setMood(.angry, in: .afternoon)
        XCTAssertEqual(viewModel.selected?.representativeMood, .angry, "오전보다 오후가 앞선다")

        viewModel.setMood(.comfort, in: .wholeDay)
        XCTAssertEqual(viewModel.selected?.representativeMood, .comfort, "하루가 가장 앞선다")
    }

    func testIntensityTogglesOffAndRejectsOutOfRange() {
        let (viewModel, _, _) = make()
        viewModel.reload()
        viewModel.setMood(.happy, in: .morning)

        viewModel.setIntensity(4, in: .morning)
        XCTAssertEqual(viewModel.selected?.record(.morning)?.intensity, 4)

        viewModel.setIntensity(4, in: .morning)
        XCTAssertNil(viewModel.selected?.record(.morning)?.intensity, "같은 값을 다시 누르면 해제")

        viewModel.setIntensity(9, in: .morning)
        XCTAssertNil(viewModel.selected?.record(.morning)?.intensity, "범위 밖 값은 버린다")
    }

    /// 감정 없이 원인만 남는 일은 없다.
    func testCauseIsIgnoredWithoutAMood() {
        let (viewModel, _, _) = make()
        viewModel.reload()

        viewModel.setCause(.work, in: .morning)

        XCTAssertNil(viewModel.selected?.record(.morning))
    }

    func testDiaryMoodGroupsExposeTheRequestedSevenAreas() {
        XCTAssertEqual(DiaryMoodGroup.allCases.count, 7)
        XCTAssertEqual(DiaryMoodGroup.bright.moods.map(\.rawValue), ["감동", "행복", "감사", "기쁨", "희망", "설렘"])
        XCTAssertEqual(DiaryMoodGroup.confident.moods.count, 6)
        XCTAssertEqual(DiaryMoodGroup.calm.moods.count, 6)
        XCTAssertEqual(DiaryMoodGroup.low.moods.count, 7)
        XCTAssertEqual(DiaryMoodGroup.worried.moods.count, 11)
        XCTAssertEqual(DiaryMoodGroup.angry.moods.count, 4)
        XCTAssertEqual(DiaryMoodGroup.tired.moods.count, 5)
        XCTAssertFalse(DiaryMoodGroup.confident.subtitle.isEmpty)
    }

    /// 예전에는 감정마다 −3…+3 점수를 매겨 이 자리에서 `[3, 2, 1]` 을 단언했다.
    /// 점수 축을 버렸으므로 **같은 데이터로 슬롯·강도·시각을 검증하도록 다시 썼다.**
    func testDiaryInsightsBuildsMoodPointsWithSlotAndIntensity() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let entries = [
            DiaryDay(
                day: today, body: "", stress: nil, sleepHours: 8, sleepSource: .manual,
                moodRecords: [
                    DiaryMoodRecord(slot: .morning, mood: .happy, cause: .work, intensity: 4),
                    DiaryMoodRecord(slot: .afternoon, mood: .angry, cause: .work, intensity: 2),
                    DiaryMoodRecord(slot: .wholeDay, mood: .comfort, intensity: nil)
                ]
            )
        ]

        let snapshot = DiaryInsightsBuilder.build(
            entries: entries,
            start: today,
            end: today.addingTimeInterval(86_400),
            calendar: calendar
        )

        XCTAssertEqual(snapshot.moodPoints.map(\.slot), [.morning, .afternoon, .wholeDay])
        XCTAssertEqual(snapshot.moodPoints.map(\.intensity), [4, 2, nil])
        XCTAssertEqual(snapshot.sleepPoints.map(\.value), [8])
        XCTAssertEqual(snapshot.causeDistribution["일"], 2)
    }

    /// 오전·오후와 하루는 다른 흐름이다. 섞이면 «오후 → 하루» 라는 가짜 전이가 생긴다.
    func testInsightsKeepDaypartAndWholeDayStreamsApart() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let entries = [
            DiaryDay(
                day: today, body: "", stress: nil, sleepHours: nil, sleepSource: nil,
                moodRecords: [
                    DiaryMoodRecord(slot: .morning, mood: .happy),
                    DiaryMoodRecord(slot: .afternoon, mood: .angry),
                    DiaryMoodRecord(slot: .wholeDay, mood: .comfort)
                ]
            )
        ]

        let snapshot = DiaryInsightsBuilder.build(
            entries: entries,
            start: today,
            end: today.addingTimeInterval(86_400),
            calendar: calendar
        )

        XCTAssertEqual(snapshot.points(in: .daypart).count, 2)
        XCTAssertEqual(snapshot.points(in: .wholeDay).count, 1)
        XCTAssertEqual(snapshot.transitions(in: .daypart).count, 1, "오전 → 오후 하나뿐")
        XCTAssertTrue(snapshot.transitions(in: .wholeDay).isEmpty, "하루는 하루끼리만 잇는다")
        XCTAssertEqual(snapshot.missingIntensityCount(in: .daypart), 2)
    }

    /// 그래프 안에서 점이 겹치지 않도록 슬롯마다 기준 시각이 다르다.
    ///
    /// **전체가 시간 순으로 정렬되지는 않는다** — 슬롯 순서는 오전 → 오후 → 하루인데
    /// 기준 시각은 9시 → 18시 → 12시라 «하루» 가 가운데 끼어든다. 두 흐름을 절대 섞지 않으므로
    /// 문제가 되지 않고, 실제로 지켜야 할 것은 **한 흐름 안에서의 시간 순서**다.
    func testMoodPointTimestampsAreOrderedWithinEachStream() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let entries = [
            DiaryDay(
                day: today, body: "", stress: nil, sleepHours: nil, sleepSource: nil,
                moodRecords: [
                    DiaryMoodRecord(slot: .morning, mood: .happy),
                    DiaryMoodRecord(slot: .wholeDay, mood: .comfort),
                    DiaryMoodRecord(slot: .afternoon, mood: .angry)
                ]
            )
        ]

        let snapshot = DiaryInsightsBuilder.build(
            entries: entries, start: today, end: today.addingTimeInterval(86_400), calendar: calendar
        )
        for stream in DiaryMoodStream.allCases {
            let timestamps = snapshot.points(in: stream).map(\.timestamp)
            XCTAssertEqual(timestamps, timestamps.sorted(), "\(stream.title) 흐름은 시간 순이어야 한다")
        }

        let hours = snapshot.moodPoints.map { calendar.component(.hour, from: $0.timestamp) }
        XCTAssertEqual(hours, [9, 18, 12], "오전 09시 · 오후 18시 · 하루 12시")
        XCTAssertEqual(Set(hours).count, 3, "기준 시각이 겹치면 점이 포개진다")
    }

    func testInsightPreviewIncludesSelectedDayAndThirteenPreviousDays() {
        let (viewModel, repository, _) = make()
        let today = day(0)
        repository.days[day(-13)] = DiaryDay(day: day(-13), body: "", stress: nil, sleepHours: 7, sleepSource: .manual, moodRecords: [DiaryMoodRecord(slot: .wholeDay, mood: .joy)])
        repository.days[today] = DiaryDay(day: today, body: "", stress: nil, sleepHours: 8, sleepSource: .manual, moodRecords: [DiaryMoodRecord(slot: .wholeDay, mood: .comfort)])

        viewModel.reload()

        XCTAssertEqual(viewModel.insightPreview.moodPoints.count, 2)
        XCTAssertEqual(viewModel.insightPreview.sleepPoints.count, 2)
        XCTAssertEqual(viewModel.insightPreview.start, day(-13))
        XCTAssertEqual(viewModel.insightPreview.end, day(1))
    }

    /// 창 밖(14일보다 이전)의 기록은 패널 카드에 들어오지 않는다.
    func testInsightPreviewExcludesEntriesOlderThanTheWindow() {
        let (viewModel, repository, _) = make()
        repository.days[day(-14)] = DiaryDay(day: day(-14), body: "", stress: nil, sleepHours: 7, sleepSource: .manual, moodRecords: [DiaryMoodRecord(slot: .wholeDay, mood: .joy)])

        viewModel.reload()

        XCTAssertTrue(viewModel.insightPreview.moodPoints.isEmpty)
    }

    func testCauseTogglesOff() {
        let (viewModel, _, _) = make()
        viewModel.reload()
        viewModel.setMood(.anxious, in: .wholeDay)

        viewModel.setCause(.study, in: .wholeDay)
        XCTAssertEqual(viewModel.selected?.record(.wholeDay)?.cause, .study)

        viewModel.setCause(.study, in: .wholeDay)
        XCTAssertNil(viewModel.selected?.record(.wholeDay)?.cause)
        XCTAssertEqual(viewModel.selected?.record(.wholeDay)?.mood, .anxious, "감정은 남는다")
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
        repository.days[yesterday] = DiaryDay(day: yesterday, body: "어제 쓴 글", stress: nil, sleepHours: nil, sleepSource: nil)
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

    /// 타임라인에서 끈 취침·기상 시각이 그대로 남는다.
    func testSetSleepWindowStoresBothEndsAndDerivedLength() {
        let (viewModel, _, _) = make()
        viewModel.reload()
        let calendar = Calendar.current
        let bed = calendar.date(byAdding: .hour, value: -1, to: viewModel.selectedDay) ?? viewModel.selectedDay
        let wake = calendar.date(byAdding: .hour, value: 7, to: viewModel.selectedDay) ?? viewModel.selectedDay

        viewModel.setSleepWindow(start: bed, end: wake)

        XCTAssertEqual(viewModel.selected?.sleepStart, bed)
        XCTAssertEqual(viewModel.selected?.sleepEnd, wake)
        XCTAssertEqual(viewModel.selected?.sleepHours ?? 0, 8, accuracy: 0.001)
        XCTAssertEqual(viewModel.selected?.sleepSource, .manual)
        XCTAssertEqual(viewModel.selected?.sleepWindow, DiarySleepWindow(start: bed, end: wake))
    }

    /// 기상이 취침보다 앞선 시각으로 들어오면 자정을 넘긴 잠으로 읽는다.
    func testSetSleepWindowRollsWakeTimePastMidnight() {
        let (viewModel, _, _) = make()
        viewModel.reload()
        let calendar = Calendar.current
        let bed = calendar.date(byAdding: .hour, value: 23, to: viewModel.selectedDay) ?? viewModel.selectedDay
        let wake = calendar.date(byAdding: .hour, value: 7, to: viewModel.selectedDay) ?? viewModel.selectedDay

        viewModel.setSleepWindow(start: bed, end: wake)

        XCTAssertEqual(viewModel.selected?.sleepHours ?? 0, 8, accuracy: 0.001)
        XCTAssertEqual(viewModel.selected?.sleepEnd, wake.addingTimeInterval(24 * 3600))
    }

    /// 잘못 찍은 수면을 지우면 길이·시각·출처가 함께 사라진다.
    func testClearSleepRemovesEveryPart() {
        let (viewModel, _, _) = make()
        viewModel.reload()
        viewModel.setSleepHours(8)

        viewModel.clearSleep()

        XCTAssertNil(viewModel.selected?.sleepHours)
        XCTAssertNil(viewModel.selected?.sleepStart)
        XCTAssertNil(viewModel.selected?.sleepEnd)
        XCTAssertNil(viewModel.selected?.sleepSource)
    }

    /// 길이만 주는 경로도 축 위에 놓일 시각을 갖는다.
    func testSetSleepHoursDerivesAWindow() {
        let (viewModel, _, _) = make()
        viewModel.reload()

        viewModel.setSleepHours(7.5)

        XCTAssertEqual(viewModel.selected?.sleepHours ?? 0, 7.5, accuracy: 0.001)
        XCTAssertNotNil(viewModel.selected?.sleepStart)
        XCTAssertNotNil(viewModel.selected?.sleepEnd)
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


// MARK: - 테스트 전용 값 조립

/// 가짜 저장소가 «한 칸만 바꾼 새 값» 을 만들 때 쓴다.
/// 실제 저장소는 `@Model` 을 제자리에서 고치지만, 값 타입에는 그런 길이 없다.
private extension DiaryDay {
    func with(body: String) -> DiaryDay {
        copy(body: body)
    }

    func with(stress: Int?) -> DiaryDay {
        copy(stress: stress)
    }

    func with(window: DiarySleepWindow?, source: DiarySleepSource) -> DiaryDay {
        DiaryDay(
            day: day,
            body: body,
            stress: stress,
            sleepHours: window?.hours,
            sleepSource: window == nil ? nil : source,
            moodRecords: moodRecords,
            sleepStart: window?.start,
            sleepEnd: window?.end
        )
    }

    func settingRecord(_ record: DiaryMoodRecord) -> DiaryDay {
        copy(moodRecords: moodRecords.filter { $0.slot != record.slot } + [record])
    }

    func removingRecord(_ slot: DiaryMoodSlot) -> DiaryDay {
        copy(moodRecords: moodRecords.filter { $0.slot != slot })
    }

    private func copy(
        body: String? = nil,
        stress: Int?? = nil,
        moodRecords: [DiaryMoodRecord]? = nil
    ) -> DiaryDay {
        DiaryDay(
            day: day,
            body: body ?? self.body,
            stress: stress ?? self.stress,
            sleepHours: sleepHours,
            sleepSource: sleepSource,
            moodRecords: moodRecords ?? self.moodRecords,
            sleepStart: sleepStart,
            sleepEnd: sleepEnd
        )
    }
}
