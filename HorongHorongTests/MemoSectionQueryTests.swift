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

    /// 타이머 탭이 쓰는 술어. **Optional `Bool` 비교가 SQL 로 번역되는지**가 관건이다.
    /// `isCompleted` 는 `Bool?` 이라 `!= true` 로 비교한다.
    func testTimerCandidatePredicateTranslates() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let active = Memo(content: "살아있는 할 일", section: .todo)
        let done = Memo(content: "끝낸 할 일", section: .todo)
        done.setCompleted(true, at: Date())
        let deleted = Memo(content: "지운 할 일", section: .todo)
        deleted.deletedAt = Date()
        for memo in [active, done, deleted] { context.insert(memo) }
        try context.save()

        let found = try context.fetch(FetchDescriptor<Memo>(predicate: #Predicate {
            $0.isCompleted != true && $0.deletedAt == nil
        }))

        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.content, "살아있는 할 일")
    }

    /// **Optional Bool 을 술어에서 다루는 법.**
    ///
    /// 이 필드는 나중에 추가돼서 그 전에 만든 기록은 값이 `nil` 이다
    /// (실측 2026-09-02: 실사용 190건 중 `isCompleted` 45건이 NULL).
    /// `!= true` 로 거르면 그 기록들이 **화면에서 조용히 사라진다.**
    func testNilFlagsAreHiddenUntilNormalized() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let fresh = Memo(content: "갓 만든 할 일", section: .todo)
        let nilled = Memo(content: "값이 비어 있는 할 일", section: .todo)
        nilled.isCompleted = nil
        context.insert(fresh)
        context.insert(nilled)
        try context.save()

        // 보정 전: `!= true` 가 NULL 인 행을 빠뜨린다.
        // SQL 3값 논리에서 `NULL != 1` 은 TRUE 가 아니라 NULL 이다.
        let before = try context.fetch(FetchDescriptor<Memo>(predicate: #Predicate {
            $0.isCompleted != true
        }))
        XCTAssertEqual(before.count, 1, "값이 빈 기록이 조용히 빠진다 — 이게 위험이다")

        // 앱 실행 시 `normalizeMemoFlags` 가 하는 일.
        let nils = try context.fetch(FetchDescriptor<Memo>(
            predicate: #Predicate { $0.isCompleted == nil }
        ))
        XCTAssertEqual(nils.count, 1, "NULL 인 행을 찾아낼 수 있어야 보정할 수 있다")
        for memo in nils {
            if memo.isCompleted == nil { memo.isCompleted = false }
        }
        try context.save()

        // 보정 후: 같은 술어가 두 건을 모두 찾는다.
        let after = try context.fetch(FetchDescriptor<Memo>(predicate: #Predicate {
            $0.isCompleted != true
        }))
        XCTAssertEqual(after.count, 2, "보정 뒤에는 빠지지 않는다")
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
