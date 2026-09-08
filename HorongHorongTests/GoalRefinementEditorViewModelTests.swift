import SwiftData
import XCTest
@testable import 호롱호롱

@MainActor
final class GoalRefinementEditorViewModelTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = HorongHorongModelSchema.make()
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeTodo(_ content: String, start: Date? = nil, deadline: Date? = nil) -> TodoItem {
        TodoItem(
            id: UUID(),
            content: content,
            startDate: start,
            deadline: deadline,
            isCompleted: false,
            completionStateChangedAt: nil,
            deletedAt: nil,
            isLinkedToReminders: false,
            reminderCalendarIdentifier: nil,
            isPinned: false,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    private func makeGoalDraft(title: String, rule: String = "규칙", dueDate: Date? = nil) -> AchievementGoalDraft {
        AchievementGoalDraft(
            title: title,
            emoji: "🏃",
            cadence: "주간",
            rule: rule,
            targetCount: 1,
            targetValueText: nil,
            periodText: nil,
            dueDate: dueDate,
            colorHex: "#E87333",
            roleName: "나",
            vision: "",
            yearGoal: nil,
            monthGoal: nil,
            linkedMemoIDs: [],
            sourceRunID: nil,
            sourceSuggestionID: nil
        )
    }

    func testInitWithTodoLoadsFields() throws {
        let container = try makeContainer()
        let todoRepo = SwiftDataTodoRepository(context: container.mainContext)
        let achievementRepo = SwiftDataAchievementRepository(context: container.mainContext)

        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let due = start.addingTimeInterval(3600)
        let todo = makeTodo("문서 작성\n상세 내용", start: start, deadline: due)

        let vm = GoalRefinementEditorViewModel(
            target: .todo(todo),
            example: "예: 구체적인 작업 작성",
            todoRepository: todoRepo,
            achievementRepository: achievementRepo
        )

        XCTAssertTrue(vm.isTodo)
        XCTAssertEqual(vm.title, "문서 작성")
        XCTAssertEqual(vm.detail, "상세 내용")
        XCTAssertTrue(vm.hasStartDate)
        XCTAssertEqual(vm.startDate, start)
        XCTAssertTrue(vm.hasDueDate)
        XCTAssertEqual(vm.dueDate, due)
        XCTAssertEqual(vm.example, "예: 구체적인 작업 작성")
    }

    func testInitWithWeeklyGoalLoadsFields() throws {
        let container = try makeContainer()
        let todoRepo = SwiftDataTodoRepository(context: container.mainContext)
        let achievementRepo = SwiftDataAchievementRepository(context: container.mainContext)

        let due = Date(timeIntervalSince1970: 1_800_000_000)
        let goal = try achievementRepo.createGoal(
            makeGoalDraft(title: "주간 운동 루틴", rule: "주 3회 달리기", dueDate: due),
            childGoalIDs: [],
            newChildTitles: []
        )

        let vm = GoalRefinementEditorViewModel(
            target: .weeklyGoal(goal),
            example: "예: 달리기 거리와 시간 정하기",
            todoRepository: todoRepo,
            achievementRepository: achievementRepo
        )

        XCTAssertFalse(vm.isTodo)
        XCTAssertEqual(vm.title, "주간 운동 루틴")
        XCTAssertEqual(vm.detail, "주 3회 달리기")
        XCTAssertFalse(vm.hasStartDate)
        XCTAssertTrue(vm.hasDueDate)
        XCTAssertEqual(vm.dueDate, due)
    }

    func testSaveValidatesEmptyTitle() throws {
        let container = try makeContainer()
        let todoRepo = SwiftDataTodoRepository(context: container.mainContext)
        let achievementRepo = SwiftDataAchievementRepository(context: container.mainContext)

        let todo = makeTodo("작업")
        let vm = GoalRefinementEditorViewModel(
            target: .todo(todo),
            example: "예시",
            todoRepository: todoRepo,
            achievementRepository: achievementRepo
        )

        vm.title = "   \n "
        let success = vm.save()

        XCTAssertFalse(success)
        XCTAssertEqual(vm.errorMessage, "제목을 입력해 주세요.")
    }

    func testSaveTodoPersistsChanges() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let todoRepo = SwiftDataTodoRepository(context: context)
        let achievementRepo = SwiftDataAchievementRepository(context: context)

        let memo = Todo(content: "원래 할 일")
        context.insert(memo)
        try context.save()

        let todoItem = try XCTUnwrap(todoRepo.todo(id: memo.id))
        let vm = GoalRefinementEditorViewModel(
            target: .todo(todoItem),
            example: "예시",
            todoRepository: todoRepo,
            achievementRepository: achievementRepo
        )

        vm.title = "구체화된 할 일"
        vm.detail = "추가 메모"
        vm.hasStartDate = true
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        vm.startDate = start
        vm.hasDueDate = true
        let deadline = start.addingTimeInterval(7200)
        vm.dueDate = deadline

        let success = vm.save()
        XCTAssertTrue(success)
        XCTAssertNil(vm.errorMessage)

        let saved = try XCTUnwrap(todoRepo.todo(id: memo.id))
        XCTAssertEqual(saved.split.title, "구체화된 할 일")
        XCTAssertEqual(saved.split.note, "추가 메모")
        XCTAssertEqual(saved.startDate, start)
        XCTAssertEqual(saved.deadline, deadline)
    }

    func testSaveWeeklyGoalPersistsChanges() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let todoRepo = SwiftDataTodoRepository(context: context)
        let achievementRepo = SwiftDataAchievementRepository(context: context)

        let created = try achievementRepo.createGoal(
            makeGoalDraft(title: "원래 목표", rule: "규칙"),
            childGoalIDs: [],
            newChildTitles: []
        )

        let vm = GoalRefinementEditorViewModel(
            target: .weeklyGoal(created),
            example: "예시",
            todoRepository: todoRepo,
            achievementRepository: achievementRepo
        )

        vm.title = "수정된 목표"
        vm.detail = "수정된 측정 기준"
        vm.hasDueDate = true
        let due = Date(timeIntervalSince1970: 1_850_000_000)
        vm.dueDate = due

        let success = vm.save()
        XCTAssertTrue(success)
        XCTAssertNil(vm.errorMessage)

        let saved = try XCTUnwrap(achievementRepo.goals().first(where: { $0.id == created.id }))
        XCTAssertEqual(saved.title, "수정된 목표")
        XCTAssertEqual(saved.rule, "수정된 측정 기준")
        XCTAssertEqual(saved.dueDate, due)
    }
}
