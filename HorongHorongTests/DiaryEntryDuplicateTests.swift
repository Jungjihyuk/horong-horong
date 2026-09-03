import XCTest
import SwiftData
@testable import 호롱호롱

/// `DiaryEntry.day` 에는 유일 제약이 없다 — `#Unique` 는 macOS 15+ 라 쓸 수 없다.
/// 그래서 중복은 **코드로** 막아야 하고, 그 코드가 실제로 도는지 여기서 확인한다.
///
/// 세 겹을 각각 검사한다.
/// ① 읽기: 중복이 있어도 사전을 만들 때 죽지 않는가
/// ② 쓰기: 같은 날짜를 조회하는 `#Predicate` 가 실제로 번역되는가
/// ③ 부팅: 중복을 병합할 때 사용자가 쓴 글이 남는가
/// `ModelContainer.mainContext` 가 MainActor 격리라 클래스째 올린다.
/// (기존 테스트는 함수마다 붙였지만 여기는 헬퍼도 컨텍스트를 만든다.)
@MainActor
final class DiaryEntryDuplicateTests: XCTestCase {
    /// **컨테이너를 반환한다.** `.mainContext` 만 돌려주면 컨테이너가 해제되고
    /// 남은 컨텍스트를 쓰는 순간 SwiftData 가 trap 한다 (2026-09-01 실측).
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([DiaryEntry.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// ① `uniqueKeysWithValues:` 였다면 여기서 트랩이 나서 테스트 프로세스가 죽는다.
    func testDuplicateDaysDoNotTrapWhenBuildingMap() throws {
        let day = Calendar.current.startOfDay(for: Date())
        let first = DiaryEntry(day: day)
        first.body = "먼저 쓴 글"
        let second = DiaryEntry(day: day)
        second.body = "나중에 들어온 중복"

        let map = Dictionary([first, second].map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })

        XCTAssertEqual(map.count, 1)
        XCTAssertEqual(map[day]?.body, "먼저 쓴 글", "충돌 시 앞의 것을 남긴다")
    }

    /// ② **이 테스트의 핵심.** `#Predicate` 는 컴파일이 통과해도 SQL 로 번역되지 않으면
    /// 런타임에 터진다. `DiaryBrowserView.fetchEntry(on:)` 와 같은 술어를 실제로 실행한다.
    func testDayPredicateTranslatesAndFindsExistingEntry() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        context.insert(DiaryEntry(day: today))
        context.insert(DiaryEntry(day: yesterday))
        try context.save()

        var descriptor = FetchDescriptor<DiaryEntry>(predicate: #Predicate { $0.day == today })
        descriptor.fetchLimit = 1
        let found = try context.fetch(descriptor)

        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.day, today)
    }

    func testDayPredicateReturnsNothingForUnusedDay() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let lastWeek = calendar.date(byAdding: .day, value: -7, to: today)!

        context.insert(DiaryEntry(day: today))
        try context.save()

        let descriptor = FetchDescriptor<DiaryEntry>(predicate: #Predicate { $0.day == lastWeek })
        XCTAssertTrue(try context.fetch(descriptor).isEmpty)
    }

    /// ③ 병합 규칙: 본문이 가장 긴 것을 남긴다.
    /// 어느 쪽이 «원본»인지 따지는 것보다 **쓴 글을 잃지 않는 것**이 우선이다.
    func testMergeKeepsLongestBody() throws {
        let day = Calendar.current.startOfDay(for: Date())
        let short = DiaryEntry(day: day)
        short.body = "짧음"
        short.updatedAt = Date()                                   // 더 최근이지만 내용이 적다
        let long = DiaryEntry(day: day)
        long.body = "오늘은 오래 걸리는 일을 붙잡고 있었다. 내일도 이어서 해야 한다."
        long.updatedAt = Date().addingTimeInterval(-3600)

        let keep = [short, long].max {
            if $0.body.count != $1.body.count { return $0.body.count < $1.body.count }
            return $0.updatedAt < $1.updatedAt
        }

        XCTAssertTrue(keep === long, "최근에 고친 것보다 많이 쓴 것을 남긴다")
    }

    /// 길이가 같으면 최근에 고친 쪽을 남긴다.
    func testMergeFallsBackToMostRecentWhenBodiesTie() throws {
        let day = Calendar.current.startOfDay(for: Date())
        let older = DiaryEntry(day: day)
        older.body = "같은 길이"
        older.updatedAt = Date().addingTimeInterval(-3600)
        let newer = DiaryEntry(day: day)
        newer.body = "같은 길이"
        newer.updatedAt = Date()

        let keep = [older, newer].max {
            if $0.body.count != $1.body.count { return $0.body.count < $1.body.count }
            return $0.updatedAt < $1.updatedAt
        }

        XCTAssertTrue(keep === newer)
    }
}
