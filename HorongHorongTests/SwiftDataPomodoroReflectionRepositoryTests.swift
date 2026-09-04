import SwiftData
import XCTest
@testable import 호롱호롱

/// 회고 저장을 **진짜 SwiftData 로** 검사한다.
///
/// 예전에는 이 규칙들이 회고 창을 띄우는 클로저 안에 있었다 — `rollback` 까지 거기서
/// 다뤘다. 확인하려면 앱을 띄우고 집중을 한 번 끝내야 했다.
@MainActor
final class SwiftDataPomodoroReflectionRepositoryTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = HorongHorongModelSchema.make()
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @discardableResult
    private func insertSession(
        _ context: ModelContext,
        linkedMemoID: UUID? = nil,
        taskTitle: String? = nil,
        category: String = "개발"
    ) -> FocusSession {
        let session = FocusSession(
            focusMinutes: 25,
            breakMinutes: 5,
            category: category,
            linkedMemoID: linkedMemoID,
            taskTitleSnapshot: taskTitle
        )
        session.endedAt = Date()
        session.completed = true
        context.insert(session)
        try? context.save()
        return session
    }

    // MARK: - 물어볼지 말지

    func testPromptCarriesSessionInfo() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataPomodoroReflectionRepository(context: context)
        let memo = Todo(content: "할 일")
        context.insert(memo)
        let session = insertSession(context, linkedMemoID: memo.id, taskTitle: "할 일", category: "학습")

        let prompt = try XCTUnwrap(repository.prompt(for: session.id))

        XCTAssertEqual(prompt.taskTitle, "할 일")
        XCTAssertTrue(prompt.isLinkedTask)
        XCTAssertTrue(prompt.canRecordLinkedTaskCompletion)
        XCTAssertEqual(prompt.suggestedAppCategory, "학습")
    }

    /// **이미 답한 세션은 다시 묻지 않는다.**
    func testPromptIsNilWhenAlreadyAnswered() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataPomodoroReflectionRepository(context: context)
        let session = insertSession(context)

        try repository.saveReflection(
            sessionID: session.id,
            focusExperience: .deeplyFocused,
            progressResult: .completedAsPlanned,
            incompleteReason: nil,
            answeredAt: Date()
        )

        XCTAssertNil(repository.prompt(for: session.id))
    }

    /// 연결이 있어도 그 할 일이 없으면 완료로 찍을 수 없다.
    func testCannotRecordCompletionWhenLinkedMemoIsGone() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataPomodoroReflectionRepository(context: context)
        let session = insertSession(context, linkedMemoID: UUID(), taskTitle: "사라진 할 일")

        let prompt = try XCTUnwrap(repository.prompt(for: session.id))

        XCTAssertTrue(prompt.isLinkedTask, "연결 자체는 남아 있다")
        XCTAssertFalse(prompt.canRecordLinkedTaskCompletion)
    }

    // MARK: - 저장

    func testSaveReflectionStoresAnswer() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataPomodoroReflectionRepository(context: context)
        let session = insertSession(context)
        let answeredAt = Date(timeIntervalSince1970: 1_800_000_000)

        try repository.saveReflection(
            sessionID: session.id,
            focusExperience: .frequentlyDistracted,
            progressResult: .littleProgress,
            incompleteReason: .externalInterruption,
            answeredAt: answeredAt
        )

        let saved = try XCTUnwrap(context.fetch(FetchDescriptor<PomodoroReflection>()).first)
        XCTAssertEqual(saved.focusSessionID, session.id)
        XCTAssertEqual(saved.progressResult, .littleProgress)
        XCTAssertEqual(saved.answeredAt, answeredAt)
    }

    /// **계획대로 끝냈고 할 일이 연결돼 있으면 그 할 일도 완료로 찍힌다.**
    func testCompletedAsPlannedCompletesLinkedTask() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataPomodoroReflectionRepository(context: context)
        let memo = Todo(content: "할 일")
        context.insert(memo)
        let session = insertSession(context, linkedMemoID: memo.id, taskTitle: "할 일")

        try repository.saveReflection(
            sessionID: session.id,
            focusExperience: .deeplyFocused,
            progressResult: .completedAsPlanned,
            incompleteReason: nil,
            answeredAt: Date()
        )

        XCTAssertTrue(memo.isCompletedValue)
    }

    /// 계획대로 못 끝냈으면 할 일은 그대로 둔다.
    func testPartialProgressLeavesLinkedTaskOpen() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataPomodoroReflectionRepository(context: context)
        let memo = Todo(content: "할 일")
        context.insert(memo)
        let session = insertSession(context, linkedMemoID: memo.id, taskTitle: "할 일")

        try repository.saveReflection(
            sessionID: session.id,
            focusExperience: .deeplyFocused,
            progressResult: .littleProgress,
            incompleteReason: .externalInterruption,
            answeredAt: Date()
        )

        XCTAssertFalse(memo.isCompletedValue)
    }

    /// 답을 남기면 「나중에 쓰기」 표시가 지워진다.
    func testSavingClearsDeferredMark() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataPomodoroReflectionRepository(context: context)
        let session = insertSession(context)

        try repository.deferReflection(sessionID: session.id, at: Date())
        XCTAssertNotNil(session.reflectionDeferredAt)

        try repository.saveReflection(
            sessionID: session.id,
            focusExperience: .deeplyFocused,
            progressResult: .completedAsPlanned,
            incompleteReason: nil,
            answeredAt: Date()
        )

        XCTAssertNil(session.reflectionDeferredAt)
    }

    /// 「나중에 쓰기」는 그 시각을 남긴다. 회고는 아직 없다.
    func testDeferMarksTimeWithoutAnswering() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataPomodoroReflectionRepository(context: context)
        let session = insertSession(context)
        let deferredAt = Date(timeIntervalSince1970: 1_800_000_000)

        try repository.deferReflection(sessionID: session.id, at: deferredAt)

        XCTAssertEqual(session.reflectionDeferredAt, deferredAt)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PomodoroReflection>()).isEmpty)
        XCTAssertNotNil(repository.prompt(for: session.id), "미룬 것은 다시 물을 수 있다")
    }

    /// 없는 세션에 미루기를 걸어도 조용히 넘어간다.
    func testDeferOnMissingSessionIsIgnored() throws {
        let container = try makeContainer()
        let repository = SwiftDataPomodoroReflectionRepository(context: container.mainContext)

        XCTAssertNoThrow(try repository.deferReflection(sessionID: UUID(), at: Date()))
    }
}
