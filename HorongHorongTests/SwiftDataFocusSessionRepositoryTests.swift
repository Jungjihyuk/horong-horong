import SwiftData
import XCTest
@testable import 호롱호롱

/// 집중 세션 저장을 **진짜 SwiftData 로** 검사한다.
///
/// 예전에는 이 규칙들이 `TimerManager`(554줄) 안에 `modelContext` 조작으로 흩어져 있어,
/// 확인하려면 앱을 띄우고 25분을 기다려야 했다.
@MainActor
final class SwiftDataFocusSessionRepositoryTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = HorongHorongModelSchema.make()
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func start(_ repository: FocusSessionRepository, linkedMemoID: UUID? = nil) -> UUID {
        repository.startFocus(
            focusMinutes: 25,
            breakMinutes: 5,
            category: "개발",
            linkedMemoID: linkedMemoID,
            taskTitleSnapshot: linkedMemoID == nil ? nil : "연결된 할 일"
        )
    }

    // MARK: - 시작과 멈춤

    func testStartCreatesSession() throws {
        let container = try makeContainer()
        let repository = SwiftDataFocusSessionRepository(context: container.mainContext)

        let id = start(repository)

        let sessions = try container.mainContext.fetch(FetchDescriptor<FocusSession>())
        XCTAssertEqual(sessions.map(\.id), [id])
        XCTAssertEqual(sessions.first?.focusMinutes, 25)
        XCTAssertFalse(try XCTUnwrap(sessions.first).completed)
    }

    /// 멈췄다 다시 시작하면 그 구간이 기록된다. 집중 시간에서 빠져야 하기 때문이다.
    func testPauseAndResumeRecordsInterval() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataFocusSessionRepository(context: context)
        let id = start(repository)

        let session = try XCTUnwrap(context.fetch(FetchDescriptor<FocusSession>()).first)
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        session.startedAt = startedAt

        repository.recordPauseStarted(id: id, at: startedAt.addingTimeInterval(600))
        repository.recordPauseEnded(id: id, at: startedAt.addingTimeInterval(1_800))

        XCTAssertNil(session.pauseStartedAt)
        XCTAssertEqual(session.pauseIntervals.count, 1)
        XCTAssertEqual(session.pauseIntervals.first?.startedAt, startedAt.addingTimeInterval(600))
    }

    /// **멈춘 채로 끝내도 구간이 닫힌다.** 안 닫으면 집중 시간이 계속 늘어난 것처럼 남는다.
    func testFinishClosesAnOpenPause() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataFocusSessionRepository(context: context)
        let id = start(repository)

        let session = try XCTUnwrap(context.fetch(FetchDescriptor<FocusSession>()).first)
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        session.startedAt = startedAt
        repository.recordPauseStarted(id: id, at: startedAt.addingTimeInterval(600))

        repository.finishFocus(
            id: id,
            endedAt: startedAt.addingTimeInterval(900),
            actualSeconds: 600,
            inputActiveSeconds: 300,
            endKind: .recordedEarly
        )

        XCTAssertNil(session.pauseStartedAt, "열린 멈춤 구간이 닫혀야 한다")
        XCTAssertEqual(session.pauseIntervals.count, 1)
    }

    // MARK: - 끝내기

    func testFinishMarksCompletedAndRecordsUsage() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataFocusSessionRepository(context: context)
        let id = start(repository)

        repository.finishFocus(
            id: id,
            endedAt: Date(),
            actualSeconds: 18 * 60 + 42,
            inputActiveSeconds: 900,
            endKind: .recordedEarly
        )

        let session = try XCTUnwrap(context.fetch(FetchDescriptor<FocusSession>()).first)
        XCTAssertTrue(session.completed)
        XCTAssertEqual(session.actualFocusSeconds, 18 * 60 + 42)
        XCTAssertEqual(session.endKind, .recordedEarly)

        // 집중 시간도 «쓴 시간» 이라 그날 통계에 들어간다.
        let records = try context.fetch(FetchDescriptor<AppUsageRecord>())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.durationSeconds, 18 * 60 + 42)
        XCTAssertEqual(records.first?.category, "개발")
    }

    /// 버리면 세션 자체가 없어진다. 통계에도 안 들어간다.
    func testDiscardRemovesSessionEntirely() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataFocusSessionRepository(context: context)
        let id = start(repository)

        repository.discardFocus(id: id)

        XCTAssertTrue(try context.fetch(FetchDescriptor<FocusSession>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<AppUsageRecord>()).isEmpty)
    }

    /// `reset` 이 부르는 경로. 끝난 시각은 찍되 **완료로 치지 않는다.**
    func testAbandonMarksEndedButNotCompleted() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataFocusSessionRepository(context: context)
        let id = start(repository)
        let endedAt = Date(timeIntervalSince1970: 1_800_000_000)

        repository.abandonFocus(id: id, endedAt: endedAt)

        let session = try XCTUnwrap(context.fetch(FetchDescriptor<FocusSession>()).first)
        XCTAssertEqual(session.endedAt, endedAt)
        XCTAssertFalse(session.completed)
    }

    /// 이미 끝낸 세션은 건드리지 않는다.
    func testAbandonSkipsCompletedSession() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataFocusSessionRepository(context: context)
        let id = start(repository)
        repository.finishFocus(
            id: id, endedAt: Date(), actualSeconds: 60,
            inputActiveSeconds: 0, endKind: .recordedEarly
        )

        repository.abandonFocus(id: id, endedAt: Date(timeIntervalSince1970: 0))

        let session = try XCTUnwrap(context.fetch(FetchDescriptor<FocusSession>()).first)
        XCTAssertTrue(session.completed)
    }

    // MARK: - 이어서 하기 판단

    /// 연결된 할 일이 아직 살아 있으면 이어서 할 수 있다.
    func testFinishReportsOpenTask() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataFocusSessionRepository(context: context)
        let memo = Todo(content: "할 일")
        context.insert(memo)
        try context.save()

        let finished = repository.finishFocus(
            id: start(repository, linkedMemoID: memo.id),
            endedAt: Date(), actualSeconds: 60, inputActiveSeconds: 0, endKind: .timerCompleted
        )

        XCTAssertEqual(finished?.linkedMemoID, memo.id)
        XCTAssertTrue(try XCTUnwrap(finished).isTaskStillOpen)
    }

    /// **끝낸 할 일로는 이어서 하기를 권하지 않는다.**
    func testFinishReportsClosedTaskWhenMemoCompleted() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataFocusSessionRepository(context: context)
        let memo = Todo(content: "할 일")
        memo.isCompletedValue = true
        context.insert(memo)
        try context.save()

        let finished = repository.finishFocus(
            id: start(repository, linkedMemoID: memo.id),
            endedAt: Date(), actualSeconds: 60, inputActiveSeconds: 0, endKind: .timerCompleted
        )

        XCTAssertFalse(try XCTUnwrap(finished).isTaskStillOpen)
    }

    func testTaskIsClosedWhenMemoDeleted() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataFocusSessionRepository(context: context)
        let memo = Todo(content: "할 일")
        memo.deletedAt = Date()
        context.insert(memo)
        try context.save()

        XCTAssertFalse(repository.isTaskStillOpen(memoID: memo.id))
        XCTAssertTrue(repository.isTaskStillOpen(memoID: nil), "연결이 없으면 막을 이유가 없다")
    }

    // MARK: - 쉬는 시간 뒤 안내

    func testHasFocusSessionAfterDate() throws {
        let container = try makeContainer()
        let repository = SwiftDataFocusSessionRepository(context: container.mainContext)
        let before = Date().addingTimeInterval(-60)

        XCTAssertFalse(repository.hasFocusSession(startingAfter: before))
        _ = start(repository)
        XCTAssertTrue(repository.hasFocusSession(startingAfter: before))
    }

    /// 생산적인 앱을 충분히 썼으면 「이어서 할까요」를 띄우지 않는다.
    func testProductiveActivityCountsOnlyAfterTheGivenTime() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let repository = SwiftDataFocusSessionRepository(context: context)
        let category = try XCTUnwrap(Constants.postBreakProductiveCategories.first)
        let base = Date(timeIntervalSince1970: 1_800_000_000)

        // 기준 시각에 걸쳐 있는 구간 — 뒤쪽 30초만 세어야 한다.
        let segment = AppUsageSegment(
            appName: "앱",
            bundleIdentifier: "com.example.app",
            category: category,
            startTime: base.addingTimeInterval(-600),
            endTime: base.addingTimeInterval(30)
        )
        context.insert(segment)
        try context.save()

        XCTAssertFalse(
            repository.hasProductiveActivity(since: base, minimumSeconds: 60),
            "기준 시각 이전은 세지 않는다"
        )
        XCTAssertTrue(repository.hasProductiveActivity(since: base, minimumSeconds: 30))
    }
}
