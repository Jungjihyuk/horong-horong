import SwiftData
import XCTest
@testable import 호롱호롱

/// 후보 조회가 **실제 SwiftData 술어로** 거르는지 본다.
///
/// 거르는 책임이 빌더에서 저장소로 옮겨왔다. 여기서 안 막으면 완료한 할일이
/// 뽀모도로 후보로 다시 올라온다.
@MainActor
final class SwiftDataPomodoroTaskRepositoryTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = HorongHorongModelSchema.make()
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    func testExcludesCompletedAndDeleted() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataPomodoroTaskRepository(context: context)

        context.insert(SecondBrainRecord(content: "살아 있는 할 일", section: .todo))
        let completed = SecondBrainRecord(content: "완료", section: .todo)
        completed.isCompletedValue = true
        context.insert(completed)
        let deleted = SecondBrainRecord(content: "최근 삭제", section: .todo)
        deleted.deletedAt = Date()
        context.insert(deleted)
        try context.save()

        XCTAssertEqual(repository.candidateMemos().map(\.content), ["살아 있는 할 일"])
    }

    /// 섹션은 안 가린다 — 쪽지에 시작일을 넣어 두고 그걸로 뽀모도로를 돌리기도 한다.
    func testIncludesEverySectionThatIsStillAlive() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataPomodoroTaskRepository(context: context)

        context.insert(SecondBrainRecord(content: "할 일", section: .todo))
        context.insert(SecondBrainRecord(content: "쪽지", section: .quickNote))
        try context.save()

        XCTAssertEqual(Set(repository.candidateMemos().map(\.content)), ["할 일", "쪽지"])
    }

    /// 목표에 묶인 id 를 모은다. 같은 할일이 여러 목표에 묶여 있어도 하나로 센다.
    func testGoalLinkedIDsAreDeduplicated() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataPomodoroTaskRepository(context: context)

        let memo = SecondBrainRecord(content: "묶인 할 일", section: .todo)
        context.insert(memo)
        context.insert(AchievementGoalRecord(title: "목표 하나", linkedMemoIDs: [memo.id]))
        context.insert(AchievementGoalRecord(title: "목표 둘", linkedMemoIDs: [memo.id]))
        try context.save()

        XCTAssertEqual(repository.goalLinkedMemoIDs(), [memo.id])
    }

    /// **저장소가 준 순서를 화면이 그대로 쓴다.** 최근에 고친 것이 위로 온다.
    func testCandidatesAreSortedByRecentlyUpdated() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataPomodoroTaskRepository(context: context)

        let older = SecondBrainRecord(content: "오래된 것", section: .todo)
        older.updatedAt = Date(timeIntervalSince1970: 1_000)
        let newer = SecondBrainRecord(content: "최근 것", section: .todo)
        newer.updatedAt = Date(timeIntervalSince1970: 2_000)
        context.insert(older)
        context.insert(newer)
        try context.save()

        XCTAssertEqual(repository.candidateMemos().map(\.content), ["최근 것", "오래된 것"])
    }
}
