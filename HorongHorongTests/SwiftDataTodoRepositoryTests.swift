import SwiftData
import XCTest
@testable import 호롱호롱

@MainActor
final class SwiftDataTodoRepositoryTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = HorongHorongModelSchema.make()
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    func testSetSchedulePersistsStartAndDeadline() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataTodoRepository(context: context)
        let memo = Memo(content: "집중할 일", section: .todo)
        context.insert(memo)
        try context.save()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let deadline = start.addingTimeInterval(90 * 60)

        try repository.setSchedule(id: memo.id, startDate: start, deadline: deadline)

        let saved = try XCTUnwrap(repository.todo(id: memo.id))
        XCTAssertEqual(saved.startDate, start)
        XCTAssertEqual(saved.deadline, deadline)
        XCTAssertEqual(saved.durationMinutes, 90)
    }

    func testSetSchedulePreventsInvertedRange() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataTodoRepository(context: context)
        let memo = Memo(content: "범위 검사", section: .todo)
        context.insert(memo)
        try context.save()
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        try repository.setSchedule(
            id: memo.id,
            startDate: start,
            deadline: start.addingTimeInterval(-60)
        )

        let saved = try XCTUnwrap(repository.todo(id: memo.id))
        XCTAssertEqual(saved.startDate, start)
        XCTAssertEqual(saved.deadline, start)
    }

    // MARK: - 빠른 기록의 «오늘 할 일»

    /// **지금 시각**으로 시작한다. 기록 창의 추가(오전 9시)와 다른 경로다.
    func testAddTodayTaskStartsNow() throws {
        let container = try makeContainer()
        let repository = SwiftDataTodoRepository(context: container.mainContext)
        let before = Date()

        let created = try repository.addTodayTask(content: "지금 할 일", icon: "📝")

        let startDate = try XCTUnwrap(created.startDate)
        XCTAssertGreaterThanOrEqual(startDate, before)
        XCTAssertLessThanOrEqual(startDate, Date())
        XCTAssertEqual(created.icon, "📝")
        XCTAssertEqual(created.content, "지금 할 일")
    }

    /// 할 일 섹션으로 들어가야 목록에 보인다.
    func testAddTodayTaskLandsInTodoSection() throws {
        let container = try makeContainer()
        let repository = SwiftDataTodoRepository(context: container.mainContext)

        try repository.addTodayTask(content: "지금 할 일", icon: nil)

        XCTAssertEqual(try repository.activeTodos(matching: "").map(\.content), ["지금 할 일"])
    }
}
