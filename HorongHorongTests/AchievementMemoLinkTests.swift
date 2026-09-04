import SwiftData
import XCTest
@testable import 호롱호롱

/// 할일과 주간 목표의 연결 규칙.
///
/// 회귀 배경(2026-09-04 제보): 할일 하나(`[호롱호롱] memo to second brain`)가 두 주간
/// 목표에 동시에 묶여 성취 타임라인에 카드가 두 번 섰고, 그 할일을 최근 삭제로 보낸 뒤에도
/// 목표에 계속 연결된 채로 보였다.
@MainActor
final class AchievementMemoLinkTests: XCTestCase {
    // MARK: - 값 만들기

    private func container() throws -> ModelContainer {
        let schema = HorongHorongModelSchema.make()
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func goalDetail(
        id: UUID = UUID(),
        title: String,
        cadence: String = "주간",
        targetCount: Int = 1,
        linkedMemoIDs: [UUID] = [],
        createdAt: Date = Date(),
        dueDate: Date? = nil,
        closedAt: Date? = nil
    ) -> AchievementGoalDetail {
        AchievementGoalDetail(
            id: id,
            title: title,
            emoji: "🎯",
            cadence: cadence,
            rule: "",
            targetCount: targetCount,
            targetValueText: nil,
            periodText: nil,
            dueDate: dueDate,
            rewardText: "",
            colorHex: "#E87333",
            roleName: "나",
            vision: "",
            yearGoal: nil,
            quarterGoal: nil,
            monthGoal: nil,
            linkedMemoIDs: linkedMemoIDs,
            createdAt: createdAt,
            updatedAt: createdAt,
            completedAt: nil,
            closedAt: closedAt,
            closedReason: closedAt == nil ? nil : .failed
        )
    }

    private func memoDetail(
        id: UUID = UUID(),
        content: String,
        isCompleted: Bool = false,
        startDate: Date? = nil
    ) -> AchievementMemoDetail {
        AchievementMemoDetail(
            id: id,
            content: content,
            icon: nil,
            startDate: startDate,
            deadline: nil,
            updatedAt: startDate ?? Date(),
            isCompleted: isCompleted
        )
    }

    private func draft(
        _ title: String,
        cadence: String = "주간",
        targetCount: Int = 1,
        linkedMemoIDs: [UUID] = []
    ) -> AchievementGoalDraft {
        AchievementGoalDraft(
            title: title,
            emoji: "🎯",
            cadence: cadence,
            rule: "",
            targetCount: targetCount,
            targetValueText: nil,
            periodText: nil,
            dueDate: nil,
            colorHex: "#E87333",
            roleName: "나",
            vision: "",
            yearGoal: nil,
            monthGoal: nil,
            linkedMemoIDs: linkedMemoIDs,
            sourceRunID: nil,
            sourceSuggestionID: nil
        )
    }

    // MARK: - 소유자 규칙

    func testFirstCreatedWeeklyGoalOwnsTheMemo() {
        let memoID = UUID()
        let early = goalDetail(
            title: "호롱호롱 대규모 리펙토링",
            linkedMemoIDs: [memoID],
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
        let late = goalDetail(
            title: "호롱호롱 사용성 개선",
            linkedMemoIDs: [memoID],
            createdAt: Date(timeIntervalSince1970: 2_000)
        )

        let owners = AchievementMemoLinkPolicy.owners(in: [late, early])

        XCTAssertEqual(owners[memoID]?.id, early.id)
    }

    func testGoalBeingEditedIsNotItsOwnCompetitor() {
        let memoID = UUID()
        let goal = goalDetail(title: "호롱호롱 사용성 개선", linkedMemoIDs: [memoID])

        let owners = AchievementMemoLinkPolicy.owners(in: [goal], excluding: goal.id)

        XCTAssertNil(owners[memoID])
    }

    func testSanitizeDropsMemoOwnedByAnotherWeeklyGoal() {
        let sharedID = UUID()
        let freeID = UUID()
        let owner = goalDetail(title: "호롱호롱 대규모 리펙토링", linkedMemoIDs: [sharedID])

        let sanitized = AchievementMemoLinkPolicy.sanitized(
            linkedMemoIDs: [sharedID, freeID],
            cadence: "주간",
            goalID: nil,
            existingGoals: [owner]
        )

        XCTAssertEqual(sanitized, [freeID])
    }

    func testSanitizeKeepsMemosTheGoalAlreadyOwns() {
        let memoID = UUID()
        let goal = goalDetail(title: "호롱호롱 사용성 개선", linkedMemoIDs: [memoID])

        let sanitized = AchievementMemoLinkPolicy.sanitized(
            linkedMemoIDs: [memoID],
            cadence: "주간",
            goalID: goal.id,
            existingGoals: [goal]
        )

        XCTAssertEqual(sanitized, [memoID])
    }

    /// 월간·연간은 할일을 직접 묶지 않고 하위 목표에서 올려 받는다.
    /// 같은 할일이 여러 상위 목표 아래에 나타나는 것은 정상이라 걸러내지 않는다.
    func testSanitizeLeavesNonWeeklyCadenceAlone() {
        let memoID = UUID()
        let owner = goalDetail(title: "주간", linkedMemoIDs: [memoID])

        let sanitized = AchievementMemoLinkPolicy.sanitized(
            linkedMemoIDs: [memoID],
            cadence: "월간",
            goalID: nil,
            existingGoals: [owner]
        )

        XCTAssertEqual(sanitized, [memoID])
    }

    func testSanitizeDropsDuplicateIDsInOneRequest() {
        let memoID = UUID()

        let sanitized = AchievementMemoLinkPolicy.sanitized(
            linkedMemoIDs: [memoID, memoID],
            cadence: "주간",
            goalID: nil,
            existingGoals: [AchievementGoalDetail]()
        )

        XCTAssertEqual(sanitized, [memoID])
    }

    // MARK: - 저장소 방어선

    func testCreateGoalCannotStealMemoFromAnotherWeeklyGoal() throws {
        let container = try container()
        let context = ModelContext(container)
        let shared = Todo(content: "[호롱호롱] memo to second brain")
        let free = Todo(content: "마이그레이션 회귀 테스트")
        context.insert(shared)
        context.insert(free)
        let repository = SwiftDataAchievementRepository(context: context)

        _ = try repository.createGoal(
            draft("호롱호롱 대규모 리펙토링", targetCount: 1, linkedMemoIDs: [shared.id]),
            childGoalIDs: [],
            newChildTitles: []
        )
        let second = try repository.createGoal(
            draft("호롱호롱 사용성 개선", targetCount: 2, linkedMemoIDs: [shared.id, free.id]),
            childGoalIDs: [],
            newChildTitles: []
        )

        XCTAssertEqual(second.linkedMemoIDs, [free.id])
        // 못 가져온 할일까지 세면 1개만 남은 목표가 2개를 요구해 영원히 달성되지 않는다.
        XCTAssertEqual(second.targetCount, 1)
    }

    func testUpdateGoalCannotStealMemoFromAnotherWeeklyGoal() throws {
        let container = try container()
        let context = ModelContext(container)
        let shared = Todo(content: "[호롱호롱] memo to second brain")
        let free = Todo(content: "마이그레이션 회귀 테스트")
        context.insert(shared)
        context.insert(free)
        let repository = SwiftDataAchievementRepository(context: context)

        _ = try repository.createGoal(
            draft("호롱호롱 대규모 리펙토링", linkedMemoIDs: [shared.id]),
            childGoalIDs: [],
            newChildTitles: []
        )
        let second = try repository.createGoal(
            draft("호롱호롱 사용성 개선", linkedMemoIDs: [free.id]),
            childGoalIDs: [],
            newChildTitles: []
        )

        repository.updateGoal(
            id: second.id,
            with: AchievementGoalEditDraft(
                title: second.title,
                emoji: second.emoji,
                rule: "",
                targetCount: 2,
                rewardText: "",
                linkedMemoIDs: [free.id, shared.id],
                dueDate: nil,
                additionalChildGoalIDs: nil
            )
        )

        let updated = try XCTUnwrap(repository.goals().first { $0.id == second.id })
        XCTAssertEqual(updated.linkedMemoIDs, [free.id])
        XCTAssertEqual(updated.targetCount, 1)
    }

    /// 자기가 이미 가진 할일을 그대로 다시 저장하는 것은 «빼앗기» 가 아니다.
    func testUpdateGoalKeepsItsOwnMemos() throws {
        let container = try container()
        let context = ModelContext(container)
        let memo = Todo(content: "[호롱호롱] memo to second brain")
        context.insert(memo)
        let repository = SwiftDataAchievementRepository(context: context)

        let goal = try repository.createGoal(
            draft("호롱호롱 사용성 개선", linkedMemoIDs: [memo.id]),
            childGoalIDs: [],
            newChildTitles: []
        )
        repository.updateGoal(
            id: goal.id,
            with: AchievementGoalEditDraft(
                title: goal.title,
                emoji: goal.emoji,
                rule: "",
                targetCount: 1,
                rewardText: "",
                linkedMemoIDs: [memo.id],
                dueDate: nil,
                additionalChildGoalIDs: nil
            )
        )

        let updated = try XCTUnwrap(repository.goals().first { $0.id == goal.id })
        XCTAssertEqual(updated.linkedMemoIDs, [memo.id])
    }

    // MARK: - 삭제한 할일

    func testDeletedMemoDropsOutOfGoalLinks() {
        let deletedID = UUID()
        let aliveID = UUID()
        let record = goalDetail(
            title: "호롱호롱 사용성 개선",
            targetCount: 2,
            linkedMemoIDs: [deletedID, aliveID]
        )
        // 최근 삭제로 보낸 할일은 저장소가 이미 떨궈서 여기 오지 않는다.
        let memos = [memoDetail(id: aliveID, content: "마이그레이션 회귀 테스트")]

        let goals = AchievementDataBuilder.goals(from: [record], memos: memos)

        XCTAssertEqual(goals.first?.sourceMemoIDs, [aliveID])
        XCTAssertEqual(goals.first?.todos.count, 1)
    }

    func testGoalStillCompletesAfterOneLinkedMemoIsDeleted() {
        let deletedID = UUID()
        let aliveID = UUID()
        let record = goalDetail(
            title: "호롱호롱 사용성 개선",
            targetCount: 2,
            linkedMemoIDs: [deletedID, aliveID]
        )
        let memos = [memoDetail(id: aliveID, content: "마이그레이션 회귀 테스트", isCompleted: true)]

        let goal = AchievementDataBuilder.goals(from: [record], memos: memos).first

        XCTAssertEqual(goal?.done, 1)
        XCTAssertEqual(goal?.total, 1)
        XCTAssertEqual(goal?.isComplete, true)
    }

    func testDeletedMemoLeavesNoTimelineCard() {
        let deletedID = UUID()
        let weekStart = Constants.mondayWeekStart(for: Date(timeIntervalSince1970: 1_772_000_000))
        let record = goalDetail(
            title: "호롱호롱 사용성 개선",
            linkedMemoIDs: [deletedID],
            createdAt: weekStart
        )

        let goals = AchievementDataBuilder.goals(from: [record], memos: [])
        let timeline = AchievementDataBuilder.timeline(
            for: goals,
            memos: [],
            weekStarting: weekStart,
            referenceDate: weekStart
        )

        XCTAssertTrue(timeline.allSatisfy { $0.todos.isEmpty })
    }

    // MARK: - 규칙 이전에 저장된 중복

    /// 저장할 때 막기 시작해도 **이미 두 목표에 묶여 저장된 데이터**는 남아 있다.
    /// 그 할일은 먼저 만든 목표에만 보이고, 늦게 만든 목표에서는 사라져야 한다.
    func testLegacyDuplicateShowsOnlyUnderTheOwningGoal() {
        let sharedID = UUID()
        let owner = goalDetail(
            title: "호롱호롱 사용성 개선",
            linkedMemoIDs: [sharedID],
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
        let later = goalDetail(
            title: "호롱호롱 대규모 리펙토링",
            linkedMemoIDs: [sharedID],
            createdAt: Date(timeIntervalSince1970: 2_000)
        )
        let memos = [memoDetail(id: sharedID, content: "test")]

        let goals = AchievementDataBuilder.goals(from: [later, owner], memos: memos)

        XCTAssertEqual(goals.first { $0.id == owner.id }?.sourceMemoIDs, [sharedID])
        XCTAssertEqual(goals.first { $0.id == later.id }?.sourceMemoIDs, [])
        XCTAssertEqual(goals.first { $0.id == later.id }?.todos.count, 0)
    }

    /// 상위 목표는 하위 주간 목표에서 할일을 올려 받는다.
    /// 주간끼리의 소유자 규칙을 상위에 그대로 걸면 그 연결이 통째로 사라진다.
    func testMonthlyGoalKeepsMemosOwnedByItsWeeklyChildren() {
        let memoID = UUID()
        let monthly = goalDetail(title: "9월 목표", cadence: "월간", linkedMemoIDs: [memoID])
        let weekly = goalDetail(title: "이번 주", linkedMemoIDs: [memoID])
        let memos = [memoDetail(id: memoID, content: "test")]

        let goals = AchievementDataBuilder.goals(from: [monthly, weekly], memos: memos)

        XCTAssertEqual(goals.first { $0.id == monthly.id }?.sourceMemoIDs, [memoID])
    }

    // MARK: - 저장소: 닫기·되돌리기·마감 연장

    func testMarkFailedIsIdempotentAndKeepsTheFirstMoment() throws {
        let container = try container()
        let context = ModelContext(container)
        let repository = SwiftDataAchievementRepository(context: context)
        let goal = try repository.createGoal(draft("주간 기록"), childGoalIDs: [], newChildTitles: [])
        let first = Date(timeIntervalSince1970: 1_000)

        repository.markFailed(ids: [goal.id], at: first, reason: .expired)
        repository.markFailed(ids: [goal.id], at: Date(timeIntervalSince1970: 9_999), reason: .failed)

        let stored = try XCTUnwrap(repository.goals().first { $0.id == goal.id })
        XCTAssertEqual(stored.closedAt, first)
        XCTAssertEqual(stored.closedReason, .expired)
    }

    func testAlreadyCompletedGoalIsNeverMarkedFailed() throws {
        let container = try container()
        let context = ModelContext(container)
        let repository = SwiftDataAchievementRepository(context: context)
        let goal = try repository.createGoal(draft("주간 기록"), childGoalIDs: [], newChildTitles: [])
        repository.markCompleted(ids: [goal.id], at: Date(timeIntervalSince1970: 500))

        repository.markFailed(ids: [goal.id], at: Date(timeIntervalSince1970: 1_000), reason: .expired)

        XCTAssertNil(repository.goals().first { $0.id == goal.id }?.closedAt)
    }

    /// 닫힌 목표에 할일을 하나 더 붙여 완료시키면 «실패인데 보상도 받는» 상태가 된다.
    func testClosedGoalCannotBeStampedCompleted() throws {
        let container = try container()
        let context = ModelContext(container)
        let repository = SwiftDataAchievementRepository(context: context)
        let goal = try repository.createGoal(draft("주간 기록"), childGoalIDs: [], newChildTitles: [])
        repository.markFailed(ids: [goal.id], at: Date(timeIntervalSince1970: 1_000), reason: .expired)

        repository.markCompleted(ids: [goal.id], at: Date(timeIntervalSince1970: 2_000))

        XCTAssertNil(repository.goals().first { $0.id == goal.id }?.completedAt)
    }

    func testReopenClearsTheClosure() throws {
        let container = try container()
        let context = ModelContext(container)
        let repository = SwiftDataAchievementRepository(context: context)
        let goal = try repository.createGoal(draft("주간 기록"), childGoalIDs: [], newChildTitles: [])
        repository.markFailed(ids: [goal.id], at: Date(timeIntervalSince1970: 1_000), reason: .expired)

        repository.reopen(ids: [goal.id])

        let stored = try XCTUnwrap(repository.goals().first { $0.id == goal.id })
        XCTAssertNil(stored.closedAt)
        XCTAssertNil(stored.closedReason)
    }

    /// 「이어서 도전」은 마감을 미루면서 닫힘도 함께 푼다.
    func testExtendDueDateReopensAndMovesTheDeadline() throws {
        let container = try container()
        let context = ModelContext(container)
        let repository = SwiftDataAchievementRepository(context: context)
        let goal = try repository.createGoal(draft("주간 기록"), childGoalIDs: [], newChildTitles: [])
        repository.markFailed(ids: [goal.id], at: Date(timeIntervalSince1970: 1_000), reason: .expired)
        let newDue = Date(timeIntervalSince1970: 5_000)

        repository.extendDueDate(id: goal.id, to: newDue)

        let stored = try XCTUnwrap(repository.goals().first { $0.id == goal.id })
        XCTAssertEqual(stored.dueDate, newDue)
        XCTAssertNil(stored.closedAt)
    }

    /// 닫힌 목표는 소유권을 놓으므로 새 목표가 같은 할일을 가져갈 수 있다.
    func testNewGoalCanTakeTodosFromAClosedGoal() throws {
        let container = try container()
        let context = ModelContext(container)
        let memo = Todo(content: "데일리 로그")
        context.insert(memo)
        let repository = SwiftDataAchievementRepository(context: context)
        let old = try repository.createGoal(
            draft("지난 주 주간 기록", linkedMemoIDs: [memo.id]),
            childGoalIDs: [],
            newChildTitles: []
        )
        repository.markFailed(ids: [old.id], at: Date(timeIntervalSince1970: 1_000), reason: .expired)

        let retry = try repository.createGoal(
            draft("이번 주 주간 기록", linkedMemoIDs: [memo.id]),
            childGoalIDs: [],
            newChildTitles: []
        )

        XCTAssertEqual(retry.linkedMemoIDs, [memo.id])
    }

    // MARK: - 못 이룬 채 닫힌 목표

    /// 마감일 없는 목표는 정리한 주가 아니라 **만든 주**의 기록으로 남는다.
    func testClosedGoalWithoutDueDateBelongsToCreatedWeek() {
        let created = Date(timeIntervalSince1970: 1_772_000_000)
        let closed = created.addingTimeInterval(14 * 24 * 60 * 60)
        let now = created.addingTimeInterval(40 * 24 * 60 * 60)
        let open = goalDetail(title: "열린 목표", createdAt: created)
        let shut = goalDetail(title: "닫힌 목표", createdAt: created, closedAt: closed)

        let goals = AchievementDataBuilder.goals(from: [open, shut], memos: [])
        let thisWeek = AchievementDataBuilder.weekStart(for: now)

        let openGoal = try? XCTUnwrap(goals.first { $0.id == open.id })
        let shutGoal = try? XCTUnwrap(goals.first { $0.id == shut.id })
        XCTAssertEqual(
            AchievementDataBuilder.goal(openGoal!, belongsToWeekStarting: thisWeek, now: now),
            true
        )
        XCTAssertEqual(
            AchievementDataBuilder.goal(shutGoal!, belongsToWeekStarting: thisWeek, now: now),
            false
        )
        XCTAssertEqual(
            AchievementDataBuilder.goal(
                shutGoal!,
                belongsToWeekStarting: AchievementDataBuilder.weekStart(for: closed),
                now: now
            ),
            false
        )
        // 정산을 다음 주 이후에 했더라도 목표를 세웠던 주의 성적으로 귀속된다.
        XCTAssertEqual(
            AchievementDataBuilder.goal(
                shutGoal!,
                belongsToWeekStarting: AchievementDataBuilder.weekStart(for: created),
                now: now
            ),
            true
        )
    }

    /// 명시한 마감일이 있으면 실패·접음 시각과 무관하게 **마감일이 속한 주**에서 끝난다.
    func testClosedGoalWithDueDateBelongsToDeadlineWeek() {
        let created = Date(timeIntervalSince1970: 1_772_000_000)
        let dueDate = created.addingTimeInterval(13 * 24 * 60 * 60)
        let closed = created.addingTimeInterval(22 * 24 * 60 * 60)
        let detail = goalDetail(
            title: "주간 기록",
            createdAt: created,
            dueDate: dueDate,
            closedAt: closed
        )
        let goal = AchievementDataBuilder.goals(from: [detail], memos: [])[0]

        XCTAssertEqual(
            AchievementDataBuilder.goal(
                goal,
                belongsToWeekStarting: AchievementDataBuilder.weekStart(for: dueDate),
                now: closed
            ),
            true
        )
        XCTAssertEqual(
            AchievementDataBuilder.goal(
                goal,
                belongsToWeekStarting: AchievementDataBuilder.weekStart(for: closed),
                now: closed
            ),
            false
        )
    }

    /// `closedAt` 이 없으면 예전과 **완전히 같은** 구간이 나와야 한다.
    func testOpenGoalSpanIsUnchanged() {
        let created = Date(timeIntervalSince1970: 1_772_000_000)
        let now = created.addingTimeInterval(30 * 24 * 60 * 60)
        let goals = AchievementDataBuilder.goals(from: [goalDetail(title: "열린 목표", createdAt: created)], memos: [])

        let span = AchievementDataBuilder.goalWeekSpan(for: goals[0], now: now)

        XCTAssertEqual(span.start, AchievementDataBuilder.weekStart(for: created))
        XCTAssertEqual(span.end, AchievementDataBuilder.weekStart(for: now))
    }

    /// 닫힌 목표가 할일을 계속 쥐고 있으면 「이번 주에 다시」로 만든 목표가 되찾지 못한다.
    func testClosedGoalReleasesTodoOwnership() {
        let memoID = UUID()
        let old = goalDetail(
            title: "지난 주 주간 기록",
            linkedMemoIDs: [memoID],
            createdAt: Date(timeIntervalSince1970: 1_000),
            closedAt: Date(timeIntervalSince1970: 2_000)
        )
        let retry = goalDetail(
            title: "이번 주 주간 기록",
            linkedMemoIDs: [memoID],
            createdAt: Date(timeIntervalSince1970: 3_000)
        )
        let memos = [memoDetail(id: memoID, content: "데일리 로그")]

        let goals = AchievementDataBuilder.goals(from: [old, retry], memos: memos)

        XCTAssertEqual(goals.first { $0.id == retry.id }?.sourceMemoIDs, [memoID])
        // 닫힌 목표는 소유권을 놓아도 저장된 연결을 그대로 보여 준다 — 지나간 주의 기록이다.
        XCTAssertEqual(goals.first { $0.id == old.id }?.sourceMemoIDs, [memoID])
    }

    // MARK: - 타임라인 중복

    /// 규칙 이전에 만들어진 데이터에는 이미 두 목표에 묶인 할일이 남아 있다.
    /// 그래도 타임라인 카드는 하나여야 한다.
    func testMemoSharedByTwoGoalsRendersOneTimelineCard() {
        let weekStart = Constants.mondayWeekStart(for: Date(timeIntervalSince1970: 1_772_000_000))
        let noon = weekStart.addingTimeInterval(12 * 60 * 60)
        let sharedID = UUID()
        let first = goalDetail(
            id: UUID(),
            title: "호롱호롱 대규모 리펙토링",
            linkedMemoIDs: [sharedID],
            createdAt: weekStart
        )
        let second = goalDetail(
            id: UUID(),
            title: "호롱호롱 사용성 개선",
            linkedMemoIDs: [sharedID],
            createdAt: weekStart
        )
        let memos = [memoDetail(id: sharedID, content: "[호롱호롱] memo to second brain", startDate: noon)]

        let goals = AchievementDataBuilder.goals(from: [first, second], memos: memos)
        let timeline = AchievementDataBuilder.timeline(
            for: goals,
            memos: memos,
            weekStarting: weekStart,
            referenceDate: noon
        )

        let cards = timeline.flatMap(\.todos).filter { $0.memoID == sharedID }
        XCTAssertEqual(cards.count, 1)
    }
}
