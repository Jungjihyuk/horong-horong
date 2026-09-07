import SwiftData
import XCTest
@testable import 호롱호롱

/// 기간 조회 predicate가 실제 SwiftData 저장소에서 날짜 경계를 올바르게 번역하는지 검사한다.
@MainActor
final class SwiftDataDiaryRepositoryTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Diary.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func date(_ day: Int) -> Date {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        return calendar.startOfDay(for: calendar.date(byAdding: .day, value: day, to: base) ?? base)
    }

    func testEntriesRangeUsesEndExclusiveBoundaryAndReverseOrder() throws {
        let container = try makeContainer()
        let context = container.mainContext
        for offset in -1...2 {
            context.insert(Diary(day: date(offset), calendar: calendar))
        }
        try context.save()

        let repository = SwiftDataDiaryRepository(context: context, calendar: calendar)
        let entries = try repository.entries(from: date(0), to: date(2))

        XCTAssertEqual(entries.map(\.day), [date(1), date(0)])
    }

    /// 수면은 «길이 · 취침 · 기상 · 출처» 네 값이 한 덩어리로 움직인다.
    /// 하나만 남으면 그래프가 시각과 길이 중 어느 쪽을 믿어야 할지 알 수 없다.
    func testSetSleepStoresWindowEndsAndDerivedLength() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataDiaryRepository(context: context, calendar: calendar)
        let day = date(0)
        let bed = day.addingTimeInterval(-3600)
        let wake = day.addingTimeInterval(7 * 3600)

        let saved = try repository.setSleep(
            on: day,
            window: DiarySleepWindow(start: bed, end: wake),
            source: .manual
        )

        XCTAssertEqual(saved.sleepStart, bed)
        XCTAssertEqual(saved.sleepEnd, wake)
        XCTAssertEqual(saved.sleepHours ?? 0, 8, accuracy: 0.001)
        XCTAssertEqual(saved.sleepSource, .manual)
        XCTAssertEqual(try repository.entry(on: day)?.sleepWindow, DiarySleepWindow(start: bed, end: wake))
    }

    func testSetSleepWithNilWindowClearsEveryPart() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataDiaryRepository(context: context, calendar: calendar)
        let day = date(0)
        try repository.setSleep(
            on: day,
            window: DiarySleepWindow(start: day.addingTimeInterval(-3600), end: day.addingTimeInterval(7 * 3600)),
            source: .manual
        )

        let cleared = try repository.setSleep(on: day, window: nil, source: .manual)

        XCTAssertNil(cleared.sleepHours)
        XCTAssertNil(cleared.sleepStart)
        XCTAssertNil(cleared.sleepEnd)
        XCTAssertNil(cleared.sleepSource)
        XCTAssertNil(try repository.entry(on: day)?.sleepWindow)
    }

    // MARK: - 감정 슬롯

    /// 세 칸은 한 행 안에서 서로 다른 필드에 앉는다.
    func testThreeMoodSlotsPersistIndependently() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataDiaryRepository(context: context, calendar: calendar)
        let day = date(0)

        try repository.setMood(on: day, slot: .morning, mood: .happy)
        try repository.setMood(on: day, slot: .afternoon, mood: .angry)
        try repository.setMood(on: day, slot: .wholeDay, mood: .comfort)
        try repository.setIntensity(on: day, slot: .morning, intensity: 5)
        try repository.setCause(on: day, slot: .afternoon, cause: .work)

        let saved = try XCTUnwrap(try repository.entry(on: day))
        XCTAssertEqual(saved.moodRecords.map(\.slot), [.morning, .afternoon, .wholeDay])
        XCTAssertEqual(saved.record(.morning)?.intensity, 5)
        XCTAssertEqual(saved.record(.afternoon)?.cause, .work)
        XCTAssertNil(saved.record(.wholeDay)?.cause)
        XCTAssertEqual(saved.representativeMood, .comfort)
    }

    /// 감정을 지우면 그 칸의 원인·강도도 함께 사라지고, 다른 칸은 그대로다.
    func testClearingOneSlotLeavesOthersIntact() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataDiaryRepository(context: context, calendar: calendar)
        let day = date(0)
        try repository.setMood(on: day, slot: .morning, mood: .happy)
        try repository.setCause(on: day, slot: .morning, cause: .work)
        try repository.setIntensity(on: day, slot: .morning, intensity: 3)
        try repository.setMood(on: day, slot: .afternoon, mood: .angry)
        try repository.setIntensity(on: day, slot: .afternoon, intensity: 2)

        try repository.setMood(on: day, slot: .morning, mood: nil)

        let saved = try XCTUnwrap(try repository.entry(on: day))
        XCTAssertNil(saved.record(.morning))
        XCTAssertEqual(saved.record(.afternoon)?.mood, .angry)
        XCTAssertEqual(saved.record(.afternoon)?.intensity, 2)
    }

    /// 감정 없이 원인·강도만 있는 행은 기록으로 읽지 않는다.
    func testCauseWithoutMoodIsNotAReadableRecord() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataDiaryRepository(context: context, calendar: calendar)
        let day = date(0)

        try repository.setCause(on: day, slot: .wholeDay, cause: .money)
        try repository.setIntensity(on: day, slot: .wholeDay, intensity: 4)

        XCTAssertTrue(try XCTUnwrap(try repository.entry(on: day)).moodRecords.isEmpty)
    }

    /// 범위(1…5) 밖의 강도는 저장되지 않는다.
    func testOutOfRangeIntensityIsDropped() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataDiaryRepository(context: context, calendar: calendar)
        let day = date(0)
        try repository.setMood(on: day, slot: .wholeDay, mood: .happy)

        try repository.setIntensity(on: day, slot: .wholeDay, intensity: 0)
        XCTAssertNil(try repository.entry(on: day)?.record(.wholeDay)?.intensity)

        try repository.setIntensity(on: day, slot: .wholeDay, intensity: 6)
        XCTAssertNil(try repository.entry(on: day)?.record(.wholeDay)?.intensity)
    }

    /// 옛 기록(슬롯이 없던 시절의 `moodRaw`)은 «하루» 칸으로 읽힌다.
    func testLegacySingleMoodReadsAsWholeDaySlot() throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(Diary(day: date(0), moodRaw: "행복", causeRaw: "일", body: "옛 일기"))
        try context.save()

        let repository = SwiftDataDiaryRepository(context: context, calendar: calendar)
        let saved = try XCTUnwrap(try repository.entry(on: date(0)))

        XCTAssertEqual(saved.moodRecords.count, 1)
        XCTAssertEqual(saved.record(.wholeDay)?.mood, .happy)
        XCTAssertEqual(saved.record(.wholeDay)?.cause, .work)
        XCTAssertNil(saved.record(.wholeDay)?.intensity)
    }

    /// 지운 자리에 하루가 두 장 생기지 않는다 — 쓰기는 모두 같은 장을 고친다.
    func testRepeatedSleepWritesKeepASingleRow() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataDiaryRepository(context: context, calendar: calendar)
        let day = date(0)

        for hour in 5...8 {
            try repository.setSleep(
                on: day,
                window: DiarySleepWindow(start: day, end: day.addingTimeInterval(Double(hour) * 3600)),
                source: .manual
            )
        }

        XCTAssertEqual(try repository.entries(from: date(0), to: date(1)).count, 1)
        XCTAssertEqual(try repository.entry(on: day)?.sleepHours ?? 0, 8, accuracy: 0.001)
    }
}
