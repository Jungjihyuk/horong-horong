import SwiftData
import XCTest
@testable import 호롱호롱

/// 기간 조회를 **진짜 SwiftData 로** 검사한다.
///
/// **`#Predicate` 는 컴파일된다고 SwiftData 로 번역되는 게 아니다(R8).** 팝오버 타임라인이
/// 이 조회에 기대므로 인메모리 컨테이너에서 fetch 가 실제로 도는지 확인한다.
@MainActor
final class SwiftDataQuickNoteRepositoryTests: XCTestCase {
    /// **컨테이너를 함께 돌려준다.** 컨테이너가 해제되면 `mainContext` 가 무효가 되어
    /// 다음 fetch 에서 프로세스가 죽는다 — 호출부가 살려 둬야 한다.
    private func makeContainer() throws -> ModelContainer {
        let schema = HorongHorongModelSchema.make()
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// `createdAt` 을 직접 정해야 기간 경계를 검사할 수 있다. `add` 는 «지금» 으로 박는다.
    private func insert(_ content: String, createdAt: Date, into context: ModelContext) {
        let record = QuickNote(content: content)
        record.createdAt = createdAt
        record.updatedAt = createdAt
        context.insert(record)
        try? context.save()
    }

    func testNotesInRangeComeBackOldestFirst() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataQuickNoteRepository(context: context)
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: Date())
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!

        insert("늦은 기록", createdAt: dayStart.addingTimeInterval(3600 * 14), into: context)
        insert("이른 기록", createdAt: dayStart.addingTimeInterval(3600 * 9), into: context)

        let notes = try repository.notes(createdBetween: dayStart, and: dayEnd)
        XCTAssertEqual(notes.map(\.content), ["이른 기록", "늦은 기록"])
    }

    /// 어제·내일 것이 섞이면 «오늘의 흐름» 이 아니게 된다.
    func testNotesOutsideRangeAreExcluded() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataQuickNoteRepository(context: context)
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: Date())
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!

        insert("어제", createdAt: dayStart.addingTimeInterval(-60), into: context)
        insert("오늘", createdAt: dayStart.addingTimeInterval(3600), into: context)
        insert("내일", createdAt: dayEnd, into: context)

        let notes = try repository.notes(createdBetween: dayStart, and: dayEnd)
        XCTAssertEqual(notes.map(\.content), ["오늘"], "끝 경계는 포함하지 않는다")
    }

    /// 기록이 없는 날에도 조회 자체는 성공해야 한다 — 화면이 빈 타임라인을 그릴 수 있어야 한다.
    func testEmptyRangeIsNotAnError() throws {
        let container = try makeContainer()
        let repository = SwiftDataQuickNoteRepository(context: container.mainContext)
        let now = Date()
        XCTAssertEqual(try repository.notes(createdBetween: now, and: now.addingTimeInterval(60)), [])
    }

    func testRecentUsesCreationTimeAndLimitInsteadOfPinnedOrUpdatedOrder() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataQuickNoteRepository(context: context)
        let base = Date().addingTimeInterval(-100)
        insert("첫째", createdAt: base, into: context)
        insert("둘째", createdAt: base.addingTimeInterval(10), into: context)
        insert("셋째", createdAt: base.addingTimeInterval(20), into: context)

        XCTAssertEqual(try repository.recent(limit: 2).map(\.content), ["셋째", "둘째"])
    }
}
