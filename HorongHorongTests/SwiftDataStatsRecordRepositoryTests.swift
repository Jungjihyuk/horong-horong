import SwiftData
import XCTest
@testable import 호롱호롱

/// 기간 기록 삭제를 **진짜 SwiftData 로** 검사한다.
///
/// 한 번에 다섯 종류를 지우는데, 예전에는 그 목록이 설정 화면 안에 있었다.
@MainActor
final class SwiftDataStatsRecordRepositoryTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = HorongHorongModelSchema.make()
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// **자정 기준으로 맞춘다.** `AppUsageRecord` 는 생성자에서 날짜를 그날 0시로 내리므로,
    /// 아무 시각이나 쓰면 그 기록만 기간 밖으로 빠져 셈이 하나 모자란다.
    private func date(_ day: Int) -> Date {
        let base = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        return Calendar.current.date(byAdding: .day, value: day, to: base) ?? base
    }

    /// 다섯 종류를 각각 하나씩 심는다.
    private func seed(_ context: ModelContext, at day: Int) {
        context.insert(AppUsageRecord(
            appName: "앱", bundleIdentifier: "com.a", category: "개발", date: date(day)
        ))
        context.insert(AppUsageSegment(
            appName: "앱", bundleIdentifier: "com.a", category: "개발",
            startTime: date(day), endTime: date(day).addingTimeInterval(60)
        ))
        let session = FocusSession(focusMinutes: 25, breakMinutes: 5, category: "개발")
        session.startedAt = date(day)
        context.insert(session)
        context.insert(AttentionEvent(
            fingerprint: "fp-\(day)",
            eventType: "selective",
            occurredAt: date(day),
            sourceApp: "앱",
            sourceCategory: "개발",
            targetCategory: nil,
            durationSeconds: 60,
            verdict: .distraction
        ))
        context.insert(AttentionDaySummary(
            day: date(day),
            dayKey: "day-\(day)",
            flowState: .steady,
            overallScore: 0.5,
            selectiveEventCount: 1,
            sustainedEventCount: 0,
            returnEventCount: 0,
            representativeReason: nil
        ))
        try? context.save()
    }

    func testCountsEveryRecordKindInRange() throws {
        let container = try makeContainer()
        seed(container.mainContext, at: 0)
        let repository = SwiftDataStatsRecordRepository(context: container.mainContext)

        XCTAssertEqual(repository.recordCount(start: date(0), end: date(1)), 5)
    }

    /// 기간 밖은 세지도 지우지도 않는다.
    func testIgnoresRecordsOutsideRange() throws {
        let container = try makeContainer()
        let context = container.mainContext
        seed(context, at: 0)
        seed(context, at: 10)
        let repository = SwiftDataStatsRecordRepository(context: context)

        XCTAssertEqual(repository.recordCount(start: date(0), end: date(1)), 5)

        try repository.deleteRecords(start: date(0), end: date(1))

        XCTAssertEqual(repository.recordCount(start: date(0), end: date(1)), 0)
        XCTAssertEqual(repository.recordCount(start: date(10), end: date(11)), 5, "기간 밖은 그대로")
    }

    func testDeleteRemovesEveryKind() throws {
        let container = try makeContainer()
        let context = container.mainContext
        seed(context, at: 0)
        let repository = SwiftDataStatsRecordRepository(context: context)

        try repository.deleteRecords(start: date(0), end: date(1))

        XCTAssertTrue(try context.fetch(FetchDescriptor<AppUsageRecord>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<AppUsageSegment>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<FocusSession>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<AttentionEvent>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<AttentionDaySummary>()).isEmpty)
    }

    /// 지울 것이 없으면 아무 일도 안 일어난다.
    func testDeletingEmptyRangeIsSafe() throws {
        let container = try makeContainer()
        let repository = SwiftDataStatsRecordRepository(context: container.mainContext)

        XCTAssertNoThrow(try repository.deleteRecords(start: date(0), end: date(1)))
        XCTAssertEqual(repository.recordCount(start: date(0), end: date(1)), 0)
    }
}
