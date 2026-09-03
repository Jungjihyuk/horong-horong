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
}
