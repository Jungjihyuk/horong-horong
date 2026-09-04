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
        createdAt: Date = Date()
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
            dueDate: nil,
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
            completedAt: nil
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
