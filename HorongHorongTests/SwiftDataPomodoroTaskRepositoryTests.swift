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

        context.insert(Todo(content: "살아 있는 할 일"))
        let completed = Todo(content: "완료")
        completed.isCompletedValue = true
        context.insert(completed)
        let deleted = Todo(content: "최근 삭제")
        deleted.deletedAt = Date()
        context.insert(deleted)
        try context.save()

        XCTAssertEqual(repository.candidateMemos().map(\.content), ["살아 있는 할 일"])
    }

    /// Todo 모델에서 살아 있는 항목들을 가져온다.
    func testIncludesEverySectionThatIsStillAlive() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataPomodoroTaskRepository(context: context)

        context.insert(Todo(content: "할 일 1"))
        context.insert(Todo(content: "할 일 2"))
        try context.save()

        XCTAssertEqual(Set(repository.candidateMemos().map(\.content)), ["할 일 1", "할 일 2"])
    }

    /// 목표에 묶인 id 를 모은다. 같은 할일이 여러 목표에 묶여 있어도 하나로 센다.
    func testGoalLinkedIDsAreDeduplicated() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataPomodoroTaskRepository(context: context)

        let memo = Todo(content: "묶인 할 일")
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

        let older = Todo(content: "오래된 것")
        older.updatedAt = Date(timeIntervalSince1970: 1_000)
        let newer = Todo(content: "최근 것")
        newer.updatedAt = Date(timeIntervalSince1970: 2_000)
        context.insert(older)
        context.insert(newer)
        try context.save()

        XCTAssertEqual(repository.candidateMemos().map(\.content), ["최근 것", "오래된 것"])
    }
}
