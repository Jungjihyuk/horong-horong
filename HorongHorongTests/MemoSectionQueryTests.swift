import XCTest
import SwiftData
@testable import 호롱호롱

/// 화면들이 `#Predicate { $0.sectionRaw == ... }` 로 DB 에서 거르게 바꿨다.
/// `#Predicate` 는 **컴파일이 통과해도 SQL 로 번역되지 않으면 런타임에 터진다.**
/// 그래서 실제로 fetch 해 본다.
@MainActor
final class MemoSectionQueryTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = HorongHorongModelSchema.make()
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func seed(_ context: ModelContext) throws {
        context.insert(Memo(content: "할 일 하나", section: .todo))
        context.insert(Memo(content: "할 일 둘", section: .todo))
        context.insert(Memo(content: "떠오른 생각", section: .quickNote))
        context.insert(Memo(content: "https://example.com", section: .reference))
        try context.save()
    }

    /// 각 화면의 술어가 자기 섹션만 가져오는가.
    func testEachSectionPredicateFetchesOnlyItsOwnRows() throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seed(context)

        let cases: [(String, Int)] = [("todo", 2), ("quickNote", 1), ("reference", 1)]
        for (raw, expected) in cases {
            let found = try context.fetch(
                FetchDescriptor<Memo>(predicate: #Predicate { $0.sectionRaw == raw })
            )
            XCTAssertEqual(found.count, expected, "\(raw) 섹션")
        }
    }

    /// 술어를 걸면 다른 섹션은 **아예 안 올라온다** — 이게 이번 변경의 목적이다.
    func testPredicateExcludesOtherSections() throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seed(context)

        let todos = try context.fetch(
            FetchDescriptor<Memo>(predicate: #Predicate { $0.sectionRaw == "todo" })
        )
        XCTAssertTrue(todos.allSatisfy { $0.resolvedSection == .todo })
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Memo>()), 4, "전체는 4건 그대로")
    }

    /// 술어는 `sectionRaw` 가 채워져 있어야 동작한다.
    /// 섹션을 안 주고 만들어도 nil 이 남지 않아야 한다 — nil 이면 어느 화면에도 안 나온다.
    func testMemoCreatedWithoutSectionStillGetsOne() throws {
        let plain = Memo(content: "섹션을 안 줬다")
        XCTAssertNotNil(plain.sectionRaw)
        XCTAssertEqual(plain.resolvedSection, .quickNote)

        let link = Memo(content: "https://example.com/article")
        XCTAssertEqual(link.resolvedSection, .reference, "내용으로 분류한다")
    }

    /// 명시적으로 준 섹션이 자동 분류를 이긴다.
    func testExplicitSectionWinsOverClassification() throws {
        let memo = Memo(content: "https://example.com", section: .todo)
        XCTAssertEqual(memo.resolvedSection, .todo)
    }

    /// 섹션 없이 만든 메모도 술어에 걸린다 — 위 두 개를 이어 붙인 확인.
    func testSectionlessMemoIsReachableByPredicate() throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(Memo(content: "컴패니언이 만든 메모"))
        try context.save()

        let found = try context.fetch(
            FetchDescriptor<Memo>(predicate: #Predicate { $0.sectionRaw == "quickNote" })
        )
        XCTAssertEqual(found.count, 1, "nil 로 남았다면 여기서 0건이 나온다")
    }
}
