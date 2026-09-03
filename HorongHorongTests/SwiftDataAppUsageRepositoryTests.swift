import SwiftData
import XCTest
@testable import 호롱호롱

/// 앱 사용 기록 저장을 **진짜 SwiftData 로** 검사한다.
///
/// 특히 자리를 비운 시간을 덜어내는 규칙이 까다롭다 — 구간 앞·뒤·전체·한가운데
/// 네 가지 경우가 있고, 예전에는 `AppTracker` 안에 한 덩어리로 있었다.
@MainActor
final class SwiftDataAppUsageRepositoryTests: XCTestCase {
    private let minimum: TimeInterval = 5

    private func makeContainer() throws -> ModelContainer {
        let schema = HorongHorongModelSchema.make()
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func date(_ offset: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_800_000_000 + offset)
    }

    private func segments(_ context: ModelContext) throws -> [AppUsageSegment] {
        try context.fetch(FetchDescriptor<AppUsageSegment>(sortBy: [SortDescriptor(\.startTime)]))
    }

    // MARK: - 구간 기록

    /// 너무 짧은 방문은 버린다. 앱을 스쳐 지나간 것까지 남기면 타임라인이 조각난다.
    func testShortVisitIsDropped() throws {
        let container = try makeContainer()
        let repository = SwiftDataAppUsageRepository(context: container.mainContext)

        let recorded = repository.recordSegment(
            appName: "앱", bundleIdentifier: "com.a", category: "개발",
            from: date(0), to: date(3), minimumSeconds: minimum
        )

        XCTAssertFalse(recorded)
        XCTAssertTrue(try segments(container.mainContext).isEmpty)
    }

    /// **바로 앞 구간이 같은 앱이면 늘린다.** 5초마다 새 구간을 만들면 안 된다.
    func testConsecutiveVisitExtendsPreviousSegment() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataAppUsageRepository(context: context)

        XCTAssertTrue(repository.recordSegment(
            appName: "앱", bundleIdentifier: "com.a", category: "개발",
            from: date(0), to: date(10), minimumSeconds: minimum
        ))
        // 앞 구간이 끝난 시각에서 이어지므로 짧아도 이어붙는다.
        XCTAssertTrue(repository.recordSegment(
            appName: "앱", bundleIdentifier: "com.a", category: "개발",
            from: date(10), to: date(12), minimumSeconds: minimum
        ))

        let stored = try segments(context)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.endTime, date(12))
    }

    /// 갈래가 다르면 잇지 않는다 — 같은 앱이어도 하는 일이 바뀐 것이다.
    func testDifferentCategoryStartsNewSegment() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataAppUsageRepository(context: context)

        _ = repository.recordSegment(
            appName: "앱", bundleIdentifier: "com.a", category: "개발",
            from: date(0), to: date(10), minimumSeconds: minimum
        )
        _ = repository.recordSegment(
            appName: "앱", bundleIdentifier: "com.a", category: "학습",
            from: date(10), to: date(20), minimumSeconds: minimum
        )

        XCTAssertEqual(try segments(context).count, 2)
    }

    // MARK: - 자리 비움 보정

    private func insertSegment(_ context: ModelContext, from start: Date, to end: Date) {
        context.insert(AppUsageSegment(
            appName: "앱", bundleIdentifier: "com.a", category: "개발",
            startTime: start, endTime: end
        ))
        try? context.save()
    }

    /// 자리 비운 시간 안에 통째로 든 구간은 지운다.
    func testSegmentFullyInsideIdleIsDeleted() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataAppUsageRepository(context: context)
        insertSegment(context, from: date(100), to: date(200))

        repository.subtractIdleTime(
            appName: "앱", bundleIdentifier: "com.a", category: "개발",
            from: date(50), to: date(300), minimumSeconds: minimum
        )

        XCTAssertTrue(try segments(context).isEmpty)
    }

    /// 뒷부분이 걸리면 끝을 당긴다.
    func testSegmentTrimmedAtEnd() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataAppUsageRepository(context: context)
        insertSegment(context, from: date(0), to: date(200))

        repository.subtractIdleTime(
            appName: "앱", bundleIdentifier: "com.a", category: "개발",
            from: date(100), to: date(300), minimumSeconds: minimum
        )

        let stored = try segments(context)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.endTime, date(100))
    }

    /// 앞부분이 걸리면 시작을 민다.
    func testSegmentTrimmedAtStart() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataAppUsageRepository(context: context)
        insertSegment(context, from: date(100), to: date(400))

        repository.subtractIdleTime(
            appName: "앱", bundleIdentifier: "com.a", category: "개발",
            from: date(0), to: date(200), minimumSeconds: minimum
        )

        let stored = try segments(context)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.startTime, date(200))
    }

    /// **한가운데가 걸리면 앞뒤로 쪼갠다.**
    func testSegmentSplitAroundIdle() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataAppUsageRepository(context: context)
        insertSegment(context, from: date(0), to: date(400))

        repository.subtractIdleTime(
            appName: "앱", bundleIdentifier: "com.a", category: "개발",
            from: date(100), to: date(300), minimumSeconds: minimum
        )

        let stored = try segments(context)
        XCTAssertEqual(stored.count, 2)
        XCTAssertEqual(stored.first?.endTime, date(100))
        XCTAssertEqual(stored.last?.startTime, date(300))
        XCTAssertEqual(stored.last?.endTime, date(400))
    }

    /// 잘라낸 조각이 너무 짧으면 남기지 않는다.
    func testTooShortRemainderIsDropped() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataAppUsageRepository(context: context)
        insertSegment(context, from: date(0), to: date(400))

        // 앞 3초 · 뒤 2초만 남는 자리 비움 → 둘 다 최소 길이 미만이다.
        repository.subtractIdleTime(
            appName: "앱", bundleIdentifier: "com.a", category: "개발",
            from: date(3), to: date(398), minimumSeconds: minimum
        )

        XCTAssertTrue(try segments(context).isEmpty)
    }

    /// 일일 사용 시간에서도 빠진다.
    func testIdleSubtractsFromDailyRecord() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataAppUsageRepository(context: context)

        repository.applyUsageDelta(
            bundleIdentifier: "com.a", appName: "앱", category: "개발",
            date: date(0), deltaSeconds: 300
        )
        repository.subtractIdleTime(
            appName: "앱", bundleIdentifier: "com.a", category: "개발",
            from: date(0), to: date(120), minimumSeconds: minimum
        )

        let records = try context.fetch(FetchDescriptor<AppUsageRecord>())
        XCTAssertEqual(records.first?.durationSeconds, 180)
    }

    // MARK: - 분류 규칙

    func testUserDefinedRulesAreReadBack() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataAppUsageRepository(context: context)

        let rule = AppCategoryRule(bundleIdentifier: "com.a", appName: "앱", category: "개발", isUserDefined: true)
        context.insert(rule)
        try context.save()

        XCTAssertEqual(
            repository.userDefinedRules(),
            [AppCategoryRuleSnapshot(bundleIdentifier: "com.a", category: "개발", isExcluded: false)]
        )
    }

    /// 옛 갈래 이름으로 저장된 것들이 지금 이름으로 옮겨진다.
    func testLegacyCategoryIsMigrated() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataAppUsageRepository(context: context)
        let legacy = Constants.legacySupportAppCategory

        context.insert(AppCategoryRule(bundleIdentifier: "com.a", appName: "앱", category: legacy, isUserDefined: true))
        context.insert(AppUsageSegment(
            appName: "앱", bundleIdentifier: "com.a", category: legacy,
            startTime: date(0), endTime: date(100)
        ))
        try context.save()

        repository.migrateLegacyProductivityManagementCategory()

        let current = Constants.productivityManagementAppCategory
        XCTAssertEqual(repository.userDefinedRules().first?.category, current)
        XCTAssertEqual(try segments(context).first?.category, current)
    }
}
